-- v0.096: 관리자 통계 (회원 수, 오늘 가입, 오늘 방문자) (서울 DB realgjj-seoul)
-- 방문자: 브라우저마다 무작위 식별값을 만들어 하루 한 번만 기록 (IP·개인정보 저장 안 함). 관리자 본인 방문은 제외.
-- 여러 번 실행해도 안전.

create table if not exists public.daily_visits (
  day date not null,
  vid text not null,
  primary key (day, vid)
);
alter table public.daily_visits enable row level security;
revoke all on public.daily_visits from anon, authenticated;

create or replace function public.log_visit(p_vid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_vid is null or p_vid !~ '^[a-z0-9-]{8,40}$' then return; end if;
  if is_admin() then return; end if;
  insert into daily_visits(day, vid) values ((now() at time zone 'Asia/Seoul')::date, p_vid) on conflict do nothing;
end $$;
revoke all on function public.log_visit(text) from public;
grant execute on function public.log_visit(text) to anon, authenticated;

create or replace function public.admin_stats() returns json
language plpgsql security definer set search_path = public, auth as $$
declare today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not is_admin() then raise exception '관리자만 볼 수 있어요'; end if;
  return json_build_object(
    'members',        (select count(*) from auth.users),
    'new_today',      (select count(*) from auth.users where (created_at at time zone 'Asia/Seoul')::date = today),
    'new_7d',         (select count(*) from auth.users where (created_at at time zone 'Asia/Seoul')::date > today - 7),
    'visits_today',   (select count(*) from daily_visits where day = today),
    'visits_yesterday',(select count(*) from daily_visits where day = today - 1),
    'visits_7d',      (select count(*) from daily_visits where day > today - 7),
    'reviews_today',  (select count(*) from reviews where (created_at at time zone 'Asia/Seoul')::date = today)
  );
end $$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

-- v0.096 추가: 리뷰·코멘트 숫자 (admin_stats를 아래로 교체)
create or replace function public.admin_stats() returns json
language plpgsql security definer set search_path = public, auth as $$
declare today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not is_admin() then raise exception '관리자만 볼 수 있어요'; end if;
  return json_build_object(
    'members',          (select count(*) from auth.users),
    'new_today',        (select count(*) from auth.users where (created_at at time zone 'Asia/Seoul')::date = today),
    'new_7d',           (select count(*) from auth.users where (created_at at time zone 'Asia/Seoul')::date > today - 7),
    'visits_today',     (select count(*) from daily_visits where day = today),
    'visits_yesterday', (select count(*) from daily_visits where day = today - 1),
    'visits_7d',        (select count(*) from daily_visits where day > today - 7),
    'reviews_today',    (select count(*) from reviews where (created_at at time zone 'Asia/Seoul')::date = today),
    'reviews_total',    (select count(*) from reviews),
    'rated_total',      (select count(*) from reviews where rating is not null),
    'comments_today',   (select count(*) from reviews where coalesce(btrim(comment), '') <> '' and (coalesce(updated_at, created_at) at time zone 'Asia/Seoul')::date = today),
    'memos_total',      (select count(*) from reviews where rating is null)
  );
end $$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;
