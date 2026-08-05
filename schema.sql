-- ============================================================
-- SETUP DATABASE — Jalankan di Supabase Dashboard > SQL Editor
-- Jalankan seluruh file ini sekali di project Supabase kamu.
-- ============================================================

-- 1) TABEL VISITORS
create table if not exists public.visitors (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  -- Data umum
  full_name text not null,
  company text not null,            -- Perusahaan / Instansi asal
  phone text not null,
  email text,
  purpose text not null,            -- Tujuan kunjungan
  host_name text not null,          -- Ditemui / bagian yang dituju
  area_visited text,                -- Area pabrik yang dikunjungi

  -- Skrining kesehatan (true = ADA gejala / berisiko)
  health_fever boolean not null default false,
  health_diarrhea_vomiting boolean not null default false,
  health_cough_cold_fever boolean not null default false,
  health_skin_wound boolean not null default false,
  health_discharge boolean not null default false,
  health_jaundice boolean not null default false,
  health_contact_infectious boolean not null default false,

  -- Hasil skrining (dihitung otomatis di aplikasi)
  health_clear boolean not null default true, -- false = perlu ditinjau petugas

  -- Kepatuhan GMP & kebersihan (hairnet, tanpa perhiasan, dsb) + persetujuan data
  gmp_compliance_agreed boolean not null default false,
  declaration_agreed boolean not null default false,

  -- Foto
  photo_url text,

  -- Status kunjungan
  check_out_at timestamptz
);

comment on table public.visitors is 'Data kunjungan tamu pabrik beserta hasil skrining kesehatan';

-- Index untuk pencarian & filter tanggal di admin dashboard
create index if not exists visitors_created_at_idx on public.visitors (created_at desc);
create index if not exists visitors_full_name_idx on public.visitors using gin (to_tsvector('simple', full_name));

-- 2) ROW LEVEL SECURITY
alter table public.visitors enable row level security;

-- Publik (form visitor, tanpa login) boleh INSERT data kunjungan sendiri
create policy "public_can_insert_visitor"
  on public.visitors
  for insert
  to anon
  with check (true);

-- Hanya user yang login (admin) yang boleh membaca / mengubah data
create policy "authenticated_can_select_visitor"
  on public.visitors
  for select
  to authenticated
  using (true);

create policy "authenticated_can_update_visitor"
  on public.visitors
  for update
  to authenticated
  using (true);

create policy "authenticated_can_delete_visitor"
  on public.visitors
  for delete
  to authenticated
  using (true);

-- 3) STORAGE BUCKET UNTUK FOTO VISITOR
insert into storage.buckets (id, name, public)
values ('visitor-photos', 'visitor-photos', false)
on conflict (id) do nothing;

-- Publik boleh upload foto (saat isi form), tapi tidak boleh membaca/menghapus
create policy "public_can_upload_visitor_photo"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'visitor-photos');

-- Hanya admin (login) yang boleh melihat & menghapus foto
create policy "authenticated_can_read_visitor_photo"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'visitor-photos');

create policy "authenticated_can_delete_visitor_photo"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'visitor-photos');

-- ============================================================
-- MIGRASI: kalau tabel `visitors` sudah pernah dibuat sebelumnya
-- dengan kolom id_number, baris ini akan menghapusnya (aman
-- dijalankan walau kolomnya sudah tidak ada / belum ada tabelnya).
alter table public.visitors drop column if exists id_number;

-- ============================================================
-- SETUP AKUN ADMIN
-- Jangan buka registrasi publik. Buat akun admin manual di:
-- Supabase Dashboard > Authentication > Users > Add user
-- Lalu login pakai email + password itu di admin.html
-- ============================================================
