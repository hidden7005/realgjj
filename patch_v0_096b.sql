-- v0.096: 리뷰를 나눠서 남길 수 있게 (서울 DB realgjj-seoul)
--  - 1번(진짜 간짜장 여부)만, 2·3·4번 별점 중 일부만, 한줄평만 남겨도 저장
--  - 평점은 남긴 별점들의 평균. 별점이 하나도 없으면 평점 없음(평균·평가 수에서 빠짐)
--  - 진짜 여부·별점·한줄평이 모두 없으면 거부
-- 여러 번 실행해도 안전.

-- 진짜 여부는 고른 경우에만 저장 (기본값 '진짜' 제거)
alter table public.reviews alter column is_real drop default;
create or replace function public.review_rating(t int, p int, k int) returns numeric
language sql immutable as $$
  select case when coalesce(t, p, k) is null then null
    else round((coalesce(t,0) + coalesce(p,0) + coalesce(k,0))::numeric
               / ((t is not null)::int + (p is not null)::int + (k is not null)::int), 1) end
$$;

create or replace function public.reviews_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  new.user_id := auth.uid();
  if new.taste is null and new.price_score is null and new.kind is null
     and new.is_real is null and coalesce(btrim(new.comment), '') = '' then
    raise exception '평가나 한줄평 중 하나는 남겨주세요';
  end if;
  new.rating := review_rating(new.taste, new.price_score, new.kind);
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
  if new.taste is null and new.price_score is null and new.kind is null
     and new.is_real is null and coalesce(btrim(new.comment), '') = '' then
    raise exception '평가나 한줄평 중 하나는 남겨주세요';
  end if;
  new.rating := review_rating(new.taste, new.price_score, new.kind);
  if not review_photo_ok(new.photo_url) or not review_photo_ok(new.photo_url2) then
    raise exception '사진 주소가 올바르지 않아요';
  end if;
  if exists (select 1 from places where id = new.place_id and hidden) then
    raise exception '지금은 평가를 받지 않는 가게예요';
  end if;
  new.updated_at := now();
  return new;
end $$;
