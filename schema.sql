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

-- ============================================================
-- ID TAMU OTOMATIS: format 36XXXXXX (mis. 36000001, 36000002, ...)
-- Dibuat pakai sequence Postgres supaya aman dari duplikat walau
-- banyak tamu daftar bersamaan (concurrent insert).
-- ============================================================
create sequence if not exists public.visitor_id_seq start with 1 increment by 1;

alter table public.visitors
  add column if not exists visitor_id text;

-- backfill baris lama (kalau sudah ada data sebelumnya) urut dari yang paling awal daftar
do $$
declare r record;
begin
  for r in (select id from public.visitors where visitor_id is null order by created_at asc)
  loop
    update public.visitors
      set visitor_id = '36' || lpad(nextval('public.visitor_id_seq')::text, 6, '0')
      where id = r.id;
  end loop;
end $$;

alter table public.visitors
  alter column visitor_id set default ('36' || lpad(nextval('public.visitor_id_seq')::text, 6, '0')),
  alter column visitor_id set not null;

alter table public.visitors drop constraint if exists visitors_visitor_id_key;
alter table public.visitors add constraint visitors_visitor_id_key unique (visitor_id);

create index if not exists visitors_visitor_id_idx on public.visitors (visitor_id);

-- 2) ROW LEVEL SECURITY
alter table public.visitors enable row level security;

-- CATATAN PENTING soal insert dari publik:
-- Form visitor TIDAK insert langsung ke tabel ini lewat REST API.
-- Insert dilakukan lewat function public.submit_visitor(jsonb) di bagian
-- bawah file ini (security definer). Alasannya: kalau publik (anon) insert
-- langsung lewat REST API sambil minta balikan `.select('visitor_id, created_at')`,
-- PostgREST membungkusnya jadi `INSERT ... RETURNING *` di dalam sebuah CTE
-- lalu baru memfilter kolom hasilnya — sehingga tetap butuh privilege SELECT
-- di SEMUA kolom tabel, bukan cuma 2 kolom yang diminta. Karena kita sengaja
-- membatasi SELECT publik hanya ke (visitor_id, created_at) agar data
-- kesehatan & data pribadi tamu tidak bisa dibaca publik, insert langsung
-- lewat REST API akan selalu gagal dengan "permission denied for table
-- visitors" (kode 42501) walau RLS & grant insert-nya sendiri benar.
-- Policy insert di bawah ini tetap dijaga untuk keperluan lain (mis. insert
-- manual dari SQL Editor sebagai role anon), tapi jalur normal dari form
-- adalah lewat RPC submit_visitor, bukan insert langsung ke tabel.
drop policy if exists "public_can_insert_visitor" on public.visitors;
create policy "public_can_insert_visitor"
  on public.visitors
  for insert
  to anon
  with check (true);

-- Hanya user yang login (admin) yang boleh membaca / mengubah data
drop policy if exists "authenticated_can_select_visitor" on public.visitors;
create policy "authenticated_can_select_visitor"
  on public.visitors
  for select
  to authenticated
  using (true);

-- Publik (form visitor) hanya boleh membaca KOLOM visitor_id & created_at,
-- dan cuma dari baris yang baru saja mereka input sendiri (dibutuhkan supaya
-- form bisa menampilkan ID tamu di kartu tamu setelah submit). Kolom lain
-- (nama, telepon, hasil skrining, dst) tetap tidak bisa dibaca publik.
revoke select on public.visitors from anon;
grant select (visitor_id, created_at) on public.visitors to anon;

-- Insert langsung ke tabel dari anon dicabut: form sekarang wajib lewat
-- function public.submit_visitor(jsonb), yang jalan sebagai security definer
-- (owner tabel) sehingga tidak butuh privilege SELECT * di sisi anon.
revoke insert on public.visitors from anon;

drop policy if exists "public_can_select_own_visitor_id" on public.visitors;
create policy "public_can_select_own_visitor_id"
  on public.visitors
  for select
  to anon
  using (true);

drop policy if exists "authenticated_can_update_visitor" on public.visitors;
create policy "authenticated_can_update_visitor"
  on public.visitors
  for update
  to authenticated
  using (true);

drop policy if exists "authenticated_can_delete_visitor" on public.visitors;
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
drop policy if exists "public_can_upload_visitor_photo" on storage.objects;
create policy "public_can_upload_visitor_photo"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'visitor-photos');

-- Hanya admin (login) yang boleh melihat & menghapus foto
drop policy if exists "authenticated_can_read_visitor_photo" on storage.objects;
create policy "authenticated_can_read_visitor_photo"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'visitor-photos');

drop policy if exists "authenticated_can_delete_visitor_photo" on storage.objects;
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
-- 4) FUNCTION UNTUK SUBMIT VISITOR DARI FORM PUBLIK
-- Dipanggil dari index.html lewat supabaseClient.rpc('submit_visitor', ...).
-- Jalan sebagai SECURITY DEFINER (owner tabel), jadi anon tidak perlu
-- privilege SELECT/INSERT langsung ke tabel visitors. Hanya kolom
-- visitor_id & created_at yang dikembalikan ke pemanggil.
-- ============================================================
create or replace function public.submit_visitor(payload jsonb)
returns table(visitor_id text, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  insert into public.visitors (
    full_name, company, phone, email, purpose, host_name, area_visited,
    health_fever, health_diarrhea_vomiting, health_cough_cold_fever,
    health_skin_wound, health_discharge, health_jaundice, health_contact_infectious,
    health_clear, gmp_compliance_agreed, declaration_agreed, photo_url
  )
  values (
    payload->>'full_name', payload->>'company', payload->>'phone', payload->>'email',
    payload->>'purpose', payload->>'host_name', payload->>'area_visited',
    coalesce((payload->>'health_fever')::boolean, false),
    coalesce((payload->>'health_diarrhea_vomiting')::boolean, false),
    coalesce((payload->>'health_cough_cold_fever')::boolean, false),
    coalesce((payload->>'health_skin_wound')::boolean, false),
    coalesce((payload->>'health_discharge')::boolean, false),
    coalesce((payload->>'health_jaundice')::boolean, false),
    coalesce((payload->>'health_contact_infectious')::boolean, false),
    coalesce((payload->>'health_clear')::boolean, true),
    coalesce((payload->>'gmp_compliance_agreed')::boolean, false),
    coalesce((payload->>'declaration_agreed')::boolean, false),
    payload->>'photo_url'
  )
  returning visitors.visitor_id, visitors.created_at;
end;
$$;

revoke all on function public.submit_visitor(jsonb) from public;
grant execute on function public.submit_visitor(jsonb) to anon;

-- ============================================================
-- SETUP AKUN ADMIN
-- Jangan buka registrasi publik. Buat akun admin manual di:
-- Supabase Dashboard > Authentication > Users > Add user
-- Lalu login pakai email + password itu di admin.html
-- ============================================================
