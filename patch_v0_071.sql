-- v0.071: 관리자 화면 (요청·신고·제보 확인 및 처리)

-- 1) 관리자 표시
alter table profiles add column if not exists is_admin boolean not null default false;
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;
grant execute on function is_admin() to authenticated, anon;

-- 2) 요청함 정리: 종류·처리 상태·연결 대상
alter table store_requests add column if not exists kind text;
alter table store_requests add column if not exists status text not null default 'new';
alter table store_requests add column if not exists ref_place uuid;
alter table store_requests add column if not exists ref_review uuid;
alter table store_requests add column if not exists payload jsonb;
alter table store_requests add column if not exists handled_at timestamptz;
alter table store_requests add column if not exists handled_by uuid;

create or replace function store_requests_set_kind() returns trigger
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
drop trigger if exists trg_store_requests_kind on store_requests;
create trigger trg_store_requests_kind before insert on store_requests
  for each row execute function store_requests_set_kind();

update store_requests set kind = case
  when name like '[등록 요청]%' then 'register'
  when name like '[리뷰 신고]%' then 'review_report'
  when name like '[제보:%' then 'place_report'
  else 'inquiry' end
where kind is null;

drop policy if exists "requests admin read" on store_requests;
create policy "requests admin read" on store_requests for select to authenticated using (is_admin());
drop policy if exists "requests admin update" on store_requests;
create policy "requests admin update" on store_requests for update to authenticated using (is_admin()) with check (is_admin());
grant select, update on store_requests to authenticated;

-- 3) 가게 숨기기 (삭제 대신, 되돌릴 수 있게)
alter table places add column if not exists hidden boolean not null default false;
drop policy if exists "places read" on places;
create policy "places read" on places for select using (hidden = false or is_admin());

create or replace function admin_set_place_hidden(p_place uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  update places set hidden = p_hidden where id = p_place;
end $$;

-- 4) 관리자 리뷰 삭제
create or replace function admin_delete_review(p_review uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_photo text;
begin
  if not is_admin() then raise exception '관리자만 할 수 있어요'; end if;
  delete from reviews where id = p_review returning photo_url into v_photo;
  return v_photo;
end $$;
drop policy if exists "review-images delete admin" on storage.objects;
create policy "review-images delete admin" on storage.objects for delete to authenticated
  using (bucket_id = 'review-images' and is_admin());

-- 5) 관리자 후보 간짜장 추가 (등록 요청 처리)
create or replace function admin_add_place(p_name text, p_address text, p_lat double precision, p_lng double precision, p_biz text)
returns uuid language plpgsql security definer set search_path = public as $$
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

revoke all on function admin_set_place_hidden(uuid, boolean) from public, anon;
revoke all on function admin_delete_review(uuid) from public, anon;
revoke all on function admin_add_place(text, text, double precision, double precision, text) from public, anon;
grant execute on function admin_set_place_hidden(uuid, boolean) to authenticated;
grant execute on function admin_delete_review(uuid) to authenticated;
grant execute on function admin_add_place(text, text, double precision, double precision, text) to authenticated;

-- 6) 관리자 지정 (닉네임 기준)
-- 관리자: 부지런한훠궈076 → 닉네임 '진짜 간짜장' (다시 뽑기 막음)
update profiles set is_admin = true, username = '진짜 간짜장', nickname_changes = 3, nickname_welcomed = true
where id = '921eea94-f858-4926-b9b8-1bb2287f445d';
