-- v0.095: 탈퇴(삭제)한 회원의 닉네임은 다시 쓰지 않음 (서울 DB realgjj-seoul)
-- 여러 번 실행해도 안전.

-- 1) 쓰지 않을 닉네임 목록 (앱에서는 읽거나 쓸 수 없음)
create table if not exists public.retired_nicknames (username text primary key, retired_at timestamptz not null default now());
alter table public.retired_nicknames enable row level security;
revoke all on public.retired_nicknames from anon, authenticated;

-- 2) 회원이 탈퇴·삭제되어 프로필이 지워지면 그 닉네임을 목록에 기록
create or replace function public.retire_nickname() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.username is not null then
    insert into retired_nicknames(username) values (old.username) on conflict do nothing;
  end if;
  return old;
end $$;
revoke all on function public.retire_nickname() from public, anon, authenticated;
drop trigger if exists trg_retire_nickname on public.profiles;
create trigger trg_retire_nickname after delete on public.profiles
  for each row execute function public.retire_nickname();

-- 3) 새 닉네임을 뽑을 때 지금 쓰는 이름과 탈퇴한 이름을 모두 피함
create or replace function public.gen_nickname() returns text
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
    exit when not exists (select 1 from profiles where username = n)
          and not exists (select 1 from retired_nicknames where username = n);
    i := i + 1;
    if i >= 30 then n := '간짜장' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8); exit; end if;
  end loop;
  return n;
end $$;
revoke all on function public.gen_nickname() from public, anon, authenticated;

-- 4) 이미 삭제한 두 계정의 닉네임도 목록에 넣음
insert into public.retired_nicknames(username) values ('느긋한하가우310'), ('바쁜찐만두951') on conflict do nothing;
