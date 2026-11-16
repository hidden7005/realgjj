-- v0.093: 문의·등록 요청·신고가 들어오면 운영자에게 이메일 알림 (서울 DB realgjj-seoul)
-- 메일 발송은 Resend(resend.com)를 사용. API 키와 받는 주소는 코드가 아니라 DB 금고(Vault)에만 저장.
-- 순서: [0]을 본인이 직접 실행(키를 채워서) → [1] → [2]. 키가 없으면 알림만 건너뛰고 문의 접수는 그대로 됨.

-- [0] 금고에 저장 (SQL Editor에서 직접. 이 두 줄은 저장소에 올리지 말 것)
-- select vault.create_secret('여기에_Resend_API_키', 'resend_api_key');
-- select vault.create_secret('알림_받을_이메일', 'notify_email');

-- [1] 외부로 요청을 보내는 확장 기능
create extension if not exists pg_net;

-- [2] 새 요청이 들어오면 메일 보내기 (실패해도 문의 접수는 막지 않음)
create or replace function public.notify_new_request() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; t text; label text; body text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  select decrypted_secret into t from vault.decrypted_secrets where name = 'notify_email' limit 1;
  if k is null or t is null then return new; end if;
  label := case new.kind when 'register' then '식당 등록 요청' when 'review_report' then '리뷰 신고'
                         when 'place_report' then '매장 제보' else '문의' end;
  body := '종류: ' || label || E'\n'
       || '제목: ' || coalesce(new.name, '') || E'\n'
       || '주소: ' || coalesce(new.address, '-') || E'\n'
       || '내용: ' || coalesce(new.note, '-') || E'\n'
       || '추가 정보: ' || coalesce(new.payload::text, '-') || E'\n'
       || '로그인 여부: ' || case when new.user_id is null then '비회원' else '회원' end || E'\n\n'
       || '관리자 화면에서 확인: https://realgjj.com';
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', '진짜간짜장 알림 <onboarding@resend.dev>',
      'to', jsonb_build_array(t),
      'subject', '[진짜간짜장] ' || label || ': ' || left(coalesce(new.name, ''), 60),
      'text', body));
  return new;
exception when others then
  return new;
end $$;
revoke all on function public.notify_new_request() from public, anon, authenticated;
drop trigger if exists trg_notify_new_request on public.store_requests;
create trigger trg_notify_new_request after insert on public.store_requests
  for each row execute function public.notify_new_request();
