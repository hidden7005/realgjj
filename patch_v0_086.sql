-- v0.086: 리뷰 사진 2장, 내 리뷰 수정 (서울 DB realgjj-seoul)
-- 순서: 이 SQL을 먼저 실행하고, 그다음 화면(v0.086)을 올릴 것 (화면이 새 열 photo_url2를 읽음)
-- 여러 번 실행해도 안전하게 작성.

-- 1) 두 번째 사진, 수정 시각
alter table public.reviews add column if not exists photo_url2 text;
alter table public.reviews add column if not exists updated_at timestamptz;

-- 2) 사진 주소 검사 (우리 저장소 주소만 허용)
create or replace function public.review_photo_ok(u text) returns boolean
language sql immutable as $$
  select u is null or u like 'https://ilvxtqhveecxpexsqhke.supabase.co/storage/v1/object/public/review-images/%'
$$;

-- 3) 리뷰 저장 전 검사 (v0.083 + 두 번째 사진)
create or replace function public.reviews_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  new.user_id := auth.uid();
  if new.taste is null or new.price_score is null or new.kind is null then
    raise exception '맛·가격·친절 별점을 모두 입력해주세요';
  end if;
  new.rating := round((new.taste + new.price_score + new.kind)::numeric / 3, 1);
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

-- 4) 리뷰 수정 전 검사: 내 리뷰만, 별점·진짜 여부·한줄평·사진만 바꿀 수 있음. 평점은 서버가 다시 계산
create or replace function public.reviews_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;  -- 운영자 직접 수정(SQL Editor)은 그대로
  if old.user_id is distinct from auth.uid() then raise exception '내 리뷰만 수정할 수 있어요'; end if;
  new.id := old.id;
  new.place_id := old.place_id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.is_seed := old.is_seed;
  if new.taste is null or new.price_score is null or new.kind is null then
    raise exception '맛·가격·친절 별점을 모두 입력해주세요';
  end if;
  new.rating := round((new.taste + new.price_score + new.kind)::numeric / 3, 1);
  if not review_photo_ok(new.photo_url) or not review_photo_ok(new.photo_url2) then
    raise exception '사진 주소가 올바르지 않아요';
  end if;
  if exists (select 1 from places where id = new.place_id and hidden) then
    raise exception '지금은 평가를 받지 않는 가게예요';
  end if;
  new.updated_at := now();
  return new;
end $$;
revoke all on function public.reviews_before_update() from public, anon, authenticated;
drop trigger if exists trg_reviews_before_update on public.reviews;
create trigger trg_reviews_before_update before update on public.reviews
  for each row execute function public.reviews_before_update();

-- 5) 수정 권한: 바꿀 수 있는 열만, 내 리뷰만
grant update (taste, price_score, kind, is_real, comment, photo_url, photo_url2) on public.reviews to authenticated;
drop policy if exists "reviews update own" on public.reviews;
create policy "reviews update own" on public.reviews for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
