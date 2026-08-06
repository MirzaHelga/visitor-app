# Aplikasi Buku Tamu Pabrik (Visitor + Skrining Kesehatan)

Web statis (HTML/CSS/JS, tanpa build step) yang terhubung ke Supabase.
Bisa langsung di-upload ke hosting statis apa pun (Netlify, Vercel, Cloudflare Pages, atau bahkan dibuka langsung dari file).

## Isi folder
- `index.html` — form visitor (data diri, skrining kesehatan, foto, GMP compliance). Bilingual ID/EN.
- `admin.html` — dashboard admin (login, lihat daftar tamu, cari/filter, export CSV, lihat foto).
- `config.js` — **wajib diisi** dengan URL & anon key Supabase kamu.
- `schema.sql` — SQL setup: tabel, RLS policy, storage bucket.
- `logo.png` — logo Savoria Kreasi Rasa, dipakai di header form & admin. Ganti file ini (nama tetap `logo.png`) kalau mau update logo.

## Tampilan Responsive
UI dibuat adaptif untuk satu codebase yang sama:
- **Android / iPhone** (termasuk notch/safe-area) — layout penuh satu kolom, tombol besar untuk dipakai di kiosk pintu masuk.
- **Tablet & Windows/desktop** — form otomatis tampil sebagai kartu terpusat (tidak melebar penuh layar), dashboard admin pakai layout tabel penuh.
- Tabel di halaman admin bisa di-scroll ke samping di layar sempit agar semua kolom tetap kebaca.
- Tidak perlu instal apa pun — cukup dibuka lewat browser (Chrome/Safari/Edge) di device apa saja.

## Langkah Setup

### 1. Jalankan `schema.sql`
Buka **Supabase Dashboard > SQL Editor**, paste seluruh isi `schema.sql`, lalu **Run**.
Ini akan membuat:
- Tabel `visitors`
- Row Level Security: publik bisa **insert** (isi form), hanya admin yang login yang bisa **select/update/delete**
- Storage bucket `visitor-photos` (private) + policy serupa

### 2. Isi `config.js`
Ambil dari **Project Settings > API**:
```js
const SUPABASE_URL = "https://xxxxxxxx.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOi...";
```
Pakai **anon/public key**, JANGAN pakai `service_role` key (itu key rahasia backend).

### 3. Buat akun admin
Supabase tidak punya halaman registrasi publik di sini — dan memang sengaja begitu.
Buat akun admin manual di **Authentication > Users > Add user** (isi email + password).
Akun ini yang dipakai untuk login di `admin.html`.

Tambah admin baru kapan saja lewat menu yang sama.

### 4. Deploy
Upload keempat file (`index.html`, `admin.html`, `config.js`, dan folder ini) ke hosting statis pilihanmu:
- **Netlify/Vercel**: drag & drop folder ini
- **Kiosk/tablet di pintu masuk pabrik**: buka `index.html` di browser, mode kiosk/fullscreen
- **Admin**: buka `admin.html` di komputer/HP petugas (login diperlukan)

## Catatan
- Foto diambil lewat kamera browser (`getUserMedia`) — perlu HTTPS untuk bekerja (kecuali di `localhost`). Hosting seperti Netlify/Vercel otomatis HTTPS.
- Foto otomatis di-compress sebelum diupload: di-resize ke maks. 1280px pada sisi terpanjang, lalu kualitas JPEG diturunkan bertahap (mulai 0.85, minimal 0.4) sampai ukuran file ≤ 400KB. Nilai ini bisa diubah lewat `PHOTO_MAX_DIM` dan `PHOTO_TARGET_BYTES` di `index.html`.
- Pertanyaan kesehatan mengacu pada praktik umum skrining tamu di industri pangan (demam, diare/muntah, infeksi kulit/luka terbuka, keluar cairan dari mata/telinga/hidung, penyakit kuning, kontak penyakit menular). Sesuaikan daftar pertanyaan di `index.html` (variabel `HEALTH_QUESTIONS`) dengan SOP HSE/QA pabrik kamu — daftar ini bukan pengganti kebijakan resmi perusahaan.
- Jawaban "Ya" pada skrining kesehatan **tidak otomatis memblokir** pendaftaran — sistem hanya menandai status "Perlu Ditinjau" agar petugas keamanan/SHE yang memutuskan.
- Nama pabrik di header `index.html` masih placeholder ("PT Nama Pabrik Anda") — ganti langsung di HTML.
- Ingin tambah fitur (misalnya scan QR untuk check-out, notifikasi ke host, dsb.)? Tinggal bilang.
