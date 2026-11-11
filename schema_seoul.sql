-- 진짜간짜장 전체 DB 구조 (서울 이전용, 2026-11-11 기준 파리 프로젝트에서 추출)
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
set search_path = public, extensions;

-- 1) 테이블
create table if not exists public.biz_master (id text not null, name text not null, branch text, kind text, road_addr text, lot_addr text, lng double precision, lat double precision);
create table if not exists public.profiles (id uuid not null, username text, created_at timestamptz default now(), nickname_changes smallint not null default 0, nickname_welcomed boolean not null default false, is_admin boolean not null default false);
create table if not exists public.places (id uuid not null default gen_random_uuid(), name text not null, kind text not null default '간짜장', price integer default 0, lat double precision not null, lng double precision not null, address text, created_at timestamptz default now(), biz_id text, created_by uuid default auth.uid(), is_seed boolean default false, proposed_price integer, proposed_votes integer default 0, hidden boolean not null default false);
create table if not exists public.reviews (id uuid not null default gen_random_uuid(), place_id uuid not null, user_id uuid default auth.uid(), rating numeric(3,1) not null, comment text, photo_path text, created_at timestamptz default now(), photo_url text, is_seed boolean default false, is_real boolean default true, taste integer, price_score integer, kind integer);
create table if not exists public.price_votes (place_id uuid not null, user_id uuid not null, price integer not null, created_at timestamptz default now());
create table if not exists public.favorites (user_id uuid not null default auth.uid(), place_id uuid not null);
create table if not exists public.follows (follower_id uuid not null default auth.uid(), followee_id uuid not null);
create table if not exists public.store_requests (id uuid not null default gen_random_uuid(), user_id uuid default auth.uid(), name text not null, address text, note text, created_at timestamptz default now(), kind text, status text not null default 'new', ref_place uuid, ref_review uuid, payload jsonb, handled_at timestamptz, handled_by uuid);

alter table public.biz_master add constraint biz_master_pkey primary key (id);
alter table public.profiles add constraint profiles_pkey primary key (id);
alter table public.profiles add constraint profiles_username_key unique (username);
alter table public.places add constraint places_pkey primary key (id);
alter table public.places add constraint places_biz_id_key unique (biz_id);
alter table public.places add constraint places_price_range check ((price is null) or ((price >= 0) and (price <= 200000)));
alter table public.places add constraint places_proposed_range check (((proposed_price is null) or ((proposed_price >= 0) and (proposed_price <= 200000))) and ((proposed_votes is null) or ((proposed_votes >= 0) and (proposed_votes <= 1000))));
alter table public.reviews add constraint reviews_pkey primary key (id);
alter table public.reviews add constraint reviews_rating_range check ((rating >= 1) and (rating <= 5));
alter table public.reviews add constraint reviews_comment_len check ((comment is null) or (char_length(comment) <= 300));
alter table public.reviews add constraint reviews_parts_range check (((taste is null) or ((taste >= 1) and (taste <= 5))) and ((price_score is null) or ((price_score >= 1) and (price_score <= 5))) and ((kind is null) or ((kind >= 1) and (kind <= 5))));
alter table public.price_votes add constraint price_votes_pkey primary key (place_id, user_id);
alter table public.favorites add constraint favorites_pkey primary key (user_id, place_id);
alter table public.follows add constraint follows_pkey primary key (follower_id, followee_id);
alter table public.follows add constraint follows_check check (follower_id <> followee_id);
alter table public.store_requests add constraint store_requests_pkey primary key (id);
alter table public.store_requests add constraint store_requests_len check ((char_length(name) <= 300) and ((address is null) or (char_length(address) <= 300)) and ((note is null) or (char_length(note) <= 3000)));

alter table public.profiles add constraint profiles_id_fkey foreign key (id) references auth.users(id) on delete cascade;
alter table public.places add constraint places_biz_id_fkey foreign key (biz_id) references biz_master(id);
alter table public.reviews add constraint reviews_place_id_fkey foreign key (place_id) references places(id) on delete cascade;
alter table public.reviews add constraint reviews_profile_fk foreign key (user_id) references profiles(id);
alter table public.reviews add constraint reviews_user_id_fkey foreign key (user_id) references auth.users(id);
alter table public.price_votes add constraint price_votes_place_id_fkey foreign key (place_id) references places(id) on delete cascade;
alter table public.price_votes add constraint price_votes_user_id_fkey foreign key (user_id) references profiles(id) on delete cascade;
alter table public.favorites add constraint favorites_place_id_fkey foreign key (place_id) references places(id) on delete cascade;
alter table public.favorites add constraint favorites_user_id_fkey foreign key (user_id) references profiles(id) on delete cascade;
alter table public.follows add constraint follows_followee_id_fkey foreign key (followee_id) references profiles(id) on delete cascade;
alter table public.follows add constraint follows_follower_id_fkey foreign key (follower_id) references profiles(id) on delete cascade;

create index biz_name_idx on public.biz_master using gin (name gin_trgm_ops);
create index idx_biz_master_coords on public.biz_master using btree (lat, lng);
create index idx_biz_master_name on public.biz_master using btree (name);
create index reviews_place_idx on public.reviews using btree (place_id);
create index reviews_user_idx on public.reviews using btree (user_id);

alter table public.biz_master enable row level security;
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.reviews enable row level security;
alter table public.price_votes enable row level security;
alter table public.favorites enable row level security;
alter table public.follows enable row level security;
alter table public.store_requests enable row level security;

-- 2) 함수
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

create or replace function gen_nickname() returns text
language plpgsql security definer set search_path = public as $$
declare
  m text[] := array['화끈한','삐진','신난','우울한','도도한','당당한','수줍은','냉정한','멍한','덜렁대는','꼼꼼한','친절한','배고픈','졸린','촉촉한','말랑한','듬직한','날씬한','뚱뚱한','털털한','똑똑한','엉뚱한','매콤한','고소한','달콤한','바삭한','쫄깃한','상큼한','짭짤한','뜨끈한','든든한','몽글한','포근한','행복한','씩씩한','용감한','느긋한','부지런한','궁금한','심심한','수상한','깜찍한','귀여운','상냥한','조용한','바쁜','빠른','반짝이는','시원한','신중한'];
  d text[] := array['탕수육','짬뽕','깐풍기','유린기','마파두부','군만두','볶음밥','울면','양장피','팔보채','크림새우','멘보샤','고추잡채','꿔바로우','깐쇼새우','라조육','라조기','유산슬','난자완스','동파육','마라탕','훠궈','딤섬','소룡포','춘권','물만두','찐만두','꽃빵','샹궈','깐풍육','칠리새우','홍소육','어향육슬','게살수프','샥스핀','북경오리','오향장육','냉채','잡채밥','잡탕밥','짬뽕밥','사천탕면','우육면','탄탄면','볶음면','고기만두','탕후루','월병','새우만두','하가우','차돌짬뽕','삼선짬뽕','깐풍새우','누룽지탕','양꼬치','부용게','해삼탕','전가복','어향가지','경장육슬','간짜장'];
  n text; i int := 0;
begin
  loop
    n := m[1 + floor(random() * array_length(m, 1))::int]
      || d[1 + floor(random() * array_length(d, 1))::int]
      || lpad((1 + floor(random() * 999))::int::text, 3, '0');
    exit when not exists (select 1 from profiles where username = n);
    i := i + 1;
    if i >= 30 then n := '간짜장' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8); exit; end if;
  end loop;
  return n;
end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, username) values (new.id, gen_nickname()) on conflict (id) do nothing;
  return new;
exception when unique_violation then
  insert into profiles(id, username)
  values (new.id, '간짜장' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)) on conflict (id) do nothing;
  return new;
end $$;

create or replace function public.reroll_nickname() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); used smallint; newname text;
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  select nickname_changes into used from profiles where id = uid for update;
  if not found then raise exception '프로필을 찾을 수 없어요'; end if;
  if used >= 3 then raise exception '닉네임은 3번까지만 바꿀 수 있어요'; end if;
  newname := gen_nickname();
  update profiles set username = newname, nickname_changes = used + 1 where id = uid;
  return json_build_object('username', newname, 'left', 3 - (used + 1));
end $$;

create or replace function public.ack_nickname_welcome() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  update profiles set nickname_welcomed = true where id = auth.uid();
end $$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '로그인이 필요해요'; end if;
  update reviews set user_id = null where user_id = uid;
  update places set created_by = null where created_by = uid;
  delete from auth.users where id = uid;
end $$;

create or replace function public.set_first_price(p_place uuid, p_price integer) returns integer
language plpgsql security definer set search_path = public as $$
declare r int;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_price is null or p_price <= 0 or p_price > 200000 then raise exception '올바른 가격이 아니에요'; end if;
  update places set price = p_price where id = p_place and (price is null or price <= 0);
  select price into r from places where id = p_place;
  return r;
end $$;

create or replace function public.propose_price(p_place uuid, p_price integer) returns void
language plpgsql security definer set search_path = public as $$
declare v places%rowtype;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  if p_price is null or p_price <= 0 or p_price > 200000 then raise exception '올바른 가격이 아니에요'; end if;
  select * into v from places where id = p_place for update;
  if not found then raise exception '가게를 찾을 수 없어요'; end if;
  if v.price is null or v.price <= 0 then raise exception '아직 등록된 가격이 없어요'; end if;
  if p_price = v.price then raise exception '현재 등록된 가격과 동일해요'; end if;
  if v.proposed_price is not null then raise exception '이미 가격 확인이 진행 중이에요'; end if;
  update places set proposed_price = p_price, proposed_votes = 1 where id = p_place;
  delete from price_votes where place_id = p_place;
  insert into price_votes(place_id, user_id, price) values (p_place, auth.uid(), p_price);
end $$;

create or replace function public.confirm_price(p_place uuid, p_price integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v places%rowtype; n int; c int;
begin
  if auth.uid() is null then raise exception '로그인이 필요해요'; end if;
  select * into v from places where id = p_place for update;
  if not found then raise exception '가게를 찾을 수 없어요'; end if;
  if v.proposed_price is null or v.proposed_price <> p_price then raise exception '확인할 가격 제안이 없어요'; end if;
  insert into price_votes(place_id, user_id, price) values (p_place, auth.uid(), p_price) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then raise exception '이미 이 가격에 투표했어요'; end if;
  select count(*) into c from price_votes where place_id = p_place and price = p_price;
  if c >= 2 then
    update places set price = p_price, proposed_price = null, proposed_votes = 0 where id = p_place;
    delete from price_votes where place_id = p_place;
    return jsonb_build_object('promoted', true, 'votes', c);
  end if;
  update places set proposed_votes = c where id = p_place;
  return jsonb_build_object('promoted', false, 'votes', c);
end $$;

create or replace function public.store_requests_set_kind() returns trigger
language plpgsql as $$
begin
  if new.kind is null then
    new.kind := case
      when new.name like '[등록 요청]%' then 'register'
      when new.name like '[리뷰 신고]%' then 'review_report'
      when new.name like '[제보:%' then 'place_report'
      else 'inquiry' end;
  end if;
  new.status := 'new';
  new.handled_at := null; new.handled_by := null;
  return new;
end $$;

create or replace function public.admin_set_place_hidden(p_place uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  update places set hidden = p_hidden where id = p_place;
end $$;

create or replace function public.admin_delete_review(p_review uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_photo text;
begin
  if not is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  delete from reviews where id = p_review returning photo_url into v_photo;
  return v_photo;
end $$;

create or replace function public.admin_add_place(p_name text, p_address text, p_lat double precision, p_lng double precision, p_biz text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  if p_biz is not null then
    select id into v_id from places where biz_id = p_biz;
    if v_id is not null then update places set hidden = false where id = v_id; return v_id; end if;
  end if;
  insert into places(name, kind, lat, lng, address, biz_id, is_seed)
  values (p_name, '간짜장', p_lat, p_lng, p_address, p_biz, true) returning id into v_id;
  return v_id;
end $$;

-- 3) 뷰
create or replace view public.place_ratings with (security_invoker = true) as
  select place_id, round(avg(rating), 1) as avg_rating, count(*) as n from reviews group by place_id;
create or replace view public.place_real_stats with (security_invoker = true) as
  select place_id, count(*) as total, count(*) filter (where is_real) as yes from reviews where is_real is not null group by place_id;

-- 4) 트리거
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
drop trigger if exists trg_store_requests_kind on public.store_requests;
create trigger trg_store_requests_kind before insert on public.store_requests for each row execute function public.store_requests_set_kind();

-- 5) 정책
create policy "biz read" on public.biz_master for select to public using (true);
create policy "profiles read" on public.profiles for select to public using (true);
create policy "places read" on public.places for select to public using ((hidden = false) or is_admin());
create policy "places insert" on public.places for insert to authenticated with check (auth.uid() = created_by);
create policy "reviews read" on public.reviews for select to public using (true);
create policy "reviews insert own" on public.reviews for insert to authenticated with check (auth.uid() = user_id);
create policy "reviews delete own" on public.reviews for delete to authenticated using (auth.uid() = user_id);
create policy "fav own read" on public.favorites for select to authenticated using (auth.uid() = user_id);
create policy "fav own add" on public.favorites for insert to authenticated with check (auth.uid() = user_id);
create policy "fav own del" on public.favorites for delete to authenticated using (auth.uid() = user_id);
create policy "follow read" on public.follows for select to public using (true);
create policy "follow add" on public.follows for insert to authenticated with check (auth.uid() = follower_id);
create policy "follow del" on public.follows for delete to authenticated using (auth.uid() = follower_id);
create policy "requests insert" on public.store_requests for insert to anon, authenticated with check ((user_id is null) or (user_id = auth.uid()));
create policy "requests admin read" on public.store_requests for select to authenticated using (is_admin());
create policy "requests admin update" on public.store_requests for update to authenticated using (is_admin()) with check (is_admin());

-- 6) 권한 (기본 권한을 걷고 필요한 것만)
revoke all on all tables in schema public from anon, authenticated;
grant select, insert, update, delete on public.biz_master, public.favorites, public.follows, public.reviews, public.store_requests to anon, authenticated;
grant select, insert, delete on public.places to anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant select on public.place_ratings, public.place_real_stats to anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.reroll_nickname(), public.ack_nickname_welcome(), public.delete_my_account() to authenticated;
grant execute on function public.set_first_price(uuid, integer), public.propose_price(uuid, integer), public.confirm_price(uuid, integer) to authenticated;
grant execute on function public.admin_set_place_hidden(uuid, boolean), public.admin_delete_review(uuid), public.admin_add_place(text, text, double precision, double precision, text) to authenticated;

-- 7) 사진 저장소
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('review-images', 'review-images', true, 3145728, '{image/jpeg}'::text[]) on conflict (id) do nothing;
create policy "review-images read" on storage.objects for select to public using (bucket_id = 'review-images');
create policy "review-images upload" on storage.objects for insert to authenticated with check (bucket_id = 'review-images');
create policy "review-images delete own" on storage.objects for delete to authenticated using ((bucket_id = 'review-images') and (owner = auth.uid()));
create policy "review-images delete admin" on storage.objects for delete to authenticated using ((bucket_id = 'review-images') and is_admin());
