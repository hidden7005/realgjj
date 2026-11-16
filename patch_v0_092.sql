-- v0.092: 별점 없이 한줄평만 남기기 (서울 DB realgjj-seoul)
-- 여러 번 실행해도 안전. 길어서 잘리지 않게 SQL Editor에는 [1], [2], [3]을 따로 실행할 것.

-- [1] 평점 없는 글 허용 + 평균·평가 수는 별점 있는 리뷰만 계산
alter table public.reviews alter column rating drop not null;
create or replace view public.place_ratings with (security_invoker = true) as
  select place_id, round(avg(rating), 1) as avg_rating, count(*) as n
  from public.reviews where rating is not null group by place_id;
grant select on public.place_ratings to anon, authenticated;

-- [2] 저장 전 검사: 별점이 하나도 없으면 한줄평 필수, 일부만 있으면 거부
create or replace function public.reviews_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  new.user_id := auth.uid();
  if new.taste is null and new.price_score is null and new.kind is null then
    if coalesce(btrim(new.comment), '') = '' then raise exception '별점을 남기거나 한줄평을 써주세요'; end if;
    new.rating := null;
    new.is_real := null;
  elsif new.taste is null or new.price_score is null or new.kind is null then
    raise exception '맛·가격·친절 별점을 모두 입력해주세요';
  else
    new.rating := round((new.taste + new.price_score + new.kind)::numeric / 3, 1);
  end if;
  new.is_seed := false;
  new.created_at := now();
  new.updated_at := null;
  if not review_photo_ok(new.photo_url) or not review_photo_ok(new.photo_url2) then
    raise exception '사진 주소가 올바르지 않아요';
  end if;
  if exists (select 1 from places where id = new.place_id and hidden) then
    raise exception '지금은 평가를 받지 않는 가게예요';
  end if;
  return new;
end $$;

-- [3] 수정 전 검사: 같은 규칙
create or replace function public.reviews_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if old.user_id is distinct from auth.uid() then raise exception '내 리뷰만 수정할 수 있어요'; end if;
  new.id := old.id;
  new.place_id := old.place_id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.is_seed := old.is_seed;
  if new.taste is null and new.price_score is null and new.kind is null then
    if coalesce(btrim(new.comment), '') = '' then raise exception '별점을 남기거나 한줄평을 써주세요'; end if;
    new.rating := null;
    new.is_real := null;
  elsif new.taste is null or new.price_score is null or new.kind is null then
    raise exception '맛·가격·친절 별점을 모두 입력해주세요';
  else
    new.rating := round((new.taste + new.price_score + new.kind)::numeric / 3, 1);
  end if;
  if not review_photo_ok(new.photo_url) or not review_photo_ok(new.photo_url2) then
    raise exception '사진 주소가 올바르지 않아요';
  end if;
  if exists (select 1 from places where id = new.place_id and hidden) then
    raise exception '지금은 평가를 받지 않는 가게예요';
  end if;
  new.updated_at := now();
  return new;
end $$;
