-- v0.095: 식당 등록 요청은 로그인한 회원만 (별점이 들어가는 요청이라). 문의·신고는 지금처럼 비회원도 가능
drop policy if exists "requests insert" on public.store_requests;
create policy "requests insert" on public.store_requests for insert to anon, authenticated
  with check (
    (user_id = auth.uid())
    or (user_id is null and coalesce(kind, case when name like '[등록 요청]%' then 'register' else 'other' end) <> 'register')
  );
