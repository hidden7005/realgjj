-- v0.066: 본인 리뷰 삭제 허용 (한 개씩, 앱에서 직접)
drop policy if exists "reviews delete own" on reviews;
create policy "reviews delete own" on reviews for delete to authenticated using (auth.uid() = user_id);
-- 본인이 올린 리뷰 사진 파일 삭제 허용
drop policy if exists "review-images delete own" on storage.objects;
create policy "review-images delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'review-images' and owner = auth.uid());
