-- v0.083: 오픈 전 어뷰징·데이터 오염 방지 (서울 DB realgjj-seoul)
-- 화면(v0.083)과 함께 반영해야 함. DB 먼저 실행하고 바로 화면을 올릴 것.
-- 여러 번 실행해도 안전하게 작성.

-- 0) 확인: 같은 가게에 같은 사람이 남긴 리뷰가 이미 2개 이상 있으면 1)이 실패함. 결과가 0행이어야 함
-- select place_id, user_id, count(*) from public.reviews where user_id is not null group by 1, 2 having count(*) > 1;

-- 1) 리뷰는 가게당 한 사람 1개 (탈퇴 회원의 익명 리뷰 user_id = null 은 제외)
create unique index if not exists reviews_place_user_uniq
  on public.reviews (place_id, user_id) where user_id is not null;

-- 2) 리뷰 저장 전 서버에서 검사·계산 (화면이 보낸 평점·시드 값은 믿지 않음)
create or replace function public.reviews_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;  -- SQL Editor 등 운영자 직접 입력은 그대로
  new.user_id := auth.uid();
  if new.taste is null or new.price_score is null or new.kind is null then
    raise exception '맛·가격·친절 별점을 모두 입력해주세요';
  end if;
  new.rating := round((new.taste + new.price_score + new.kind)::numeric / 3, 1);
  new.is_seed := false;
  new.created_at := now();
  if new.photo_url is not null and new.photo_url not like 'https://ilvxtqhveecxpexsqhke.supabase.co/storage/v1/object/public/review-images/%' then
    raise exception '사진 주소가 올바르지 않아요';
  end if;
  if exists (select 1 from places where id = new.place_id and hidden) then
    raise exception '지금은 평가를 받지 않는 가게예요';
  end if;
  return new;
end $$;
revoke all on function public.reviews_before_insert() from public, anon, authenticated;
drop trigger if exists trg_reviews_before_insert on public.reviews;
create trigger trg_reviews_before_insert before insert on public.reviews
  for each row execute function public.reviews_before_insert();

-- 3) 가게 등록은 공공데이터(biz_master)에 있는 가게만. 이름·주소·좌표는 서버가 채움
create or replace function public.places_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare b biz_master%rowtype; ex places%rowtype;
begin
  if auth.uid() is null or is_admin() then return new; end if;  -- 운영자·관리자(admin_add_place)는 그대로
  if new.biz_id is null then raise exception '등록할 수 없는 가게예요'; end if;
  select * into b from biz_master where id = new.biz_id;
  if not found then raise exception '등록할 수 없는 가게예요'; end if;
  select * into ex from places where biz_id = new.biz_id;
  if found then
    if ex.hidden then raise exception '지금은 평가를 받지 않는 가게예요'; end if;
    raise exception '이미 등록된 가게예요';
  end if;
  new.name := b.name || coalesce(' ' || nullif(b.branch, ''), '');
  new.address := coalesce(b.road_addr, b.lot_addr);
  new.lat := b.lat;
  new.lng := b.lng;
  new.kind := '간짜장';
  new.created_by := auth.uid();
  new.created_at := now();
  new.is_seed := false;
  new.hidden := false;
  new.proposed_price := null;
  new.proposed_votes := 0;
  return new;
end $$;
revoke all on function public.places_before_insert() from public, anon, authenticated;
drop trigger if exists trg_places_before_insert on public.places;
create trigger trg_places_before_insert before insert on public.places
  for each row execute function public.places_before_insert();

-- 4) 리뷰의 회원 연결을 하나로: 회원이 지워지면 리뷰는 익명(user_id = null)으로 남김
--    (auth.users 삭제 → profiles 삭제(cascade) → reviews.user_id = null)
alter table public.reviews drop constraint if exists reviews_user_id_fkey;
alter table public.reviews drop constraint if exists reviews_profile_fk;
alter table public.reviews add constraint reviews_profile_fk
  foreign key (user_id) references public.profiles(id) on delete set null;

-- 5) 권한 최소화 (접근 규칙(RLS)과 함께 이중으로 막음)
revoke all on public.biz_master, public.places, public.reviews, public.favorites, public.follows, public.store_requests from anon, authenticated;
grant select on public.biz_master, public.places, public.reviews, public.follows to anon, authenticated;
grant insert on public.places to authenticated;
grant insert, delete on public.reviews to authenticated;
grant select, insert, delete on public.favorites to authenticated;
grant insert, delete on public.follows to authenticated;
grant insert on public.store_requests to anon, authenticated;
grant select, update on public.store_requests to authenticated;

-- 6) 관리자 여부(is_admin) 열은 공개하지 않음. 앱은 is_admin() 함수로 확인
revoke select on public.profiles from anon, authenticated;
grant select (id, username, created_at, nickname_changes, nickname_welcomed) on public.profiles to anon, authenticated;
