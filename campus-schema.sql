-- Spanish with Ignasi Online Campus schema
-- Run in Supabase SQL Editor AFTER the existing schema.sql.
create table if not exists public.campus_courses(
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null references auth.users(id) on delete cascade,
 title text not null,
 description text not null default '',
 category text not null default 'General',
 level text not null default 'All levels',
 price_eur numeric(10,2) not null default 0 check(price_eur>=0),
 cover_image text,
 checkout_url text,
 outcomes text not null default '',
 is_published boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.campus_lessons(
 id uuid primary key default gen_random_uuid(),
 course_id uuid not null references public.campus_courses(id) on delete cascade,
 title text not null,
 video_url text,
 duration_minutes integer,
 content text not null default '',
 image_url text,
 is_preview boolean not null default false,
 sort_order integer not null default 0,
 created_at timestamptz not null default now()
);
create table if not exists public.campus_enrolments(
 id uuid primary key default gen_random_uuid(),
 course_id uuid not null references public.campus_courses(id) on delete cascade,
 student_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','active','revoked')),
 completed_lesson_ids uuid[] not null default '{}',
 created_at timestamptz not null default now(),
 unique(course_id,student_id)
);
create table if not exists public.campus_certificates(
 id uuid primary key default gen_random_uuid(),
 course_id uuid not null references public.campus_courses(id) on delete cascade,
 student_id uuid not null references auth.users(id) on delete cascade,
 course_title text not null,
 status text not null default 'requested' check(status in ('requested','approved','declined')),
 created_at timestamptz not null default now(),
 unique(course_id,student_id)
);
alter table public.campus_courses enable row level security;
alter table public.campus_lessons enable row level security;
alter table public.campus_enrolments enable row level security;
alter table public.campus_certificates enable row level security;
create or replace function public.campus_is_teacher() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='teacher'); $$;
drop policy if exists "Published courses visible to everyone" on public.campus_courses;
create policy "Published courses visible to everyone" on public.campus_courses for select using(is_published or created_by=auth.uid() or public.campus_is_teacher());
drop policy if exists "Teachers create courses" on public.campus_courses;
create policy "Teachers create courses" on public.campus_courses for insert to authenticated with check(public.campus_is_teacher() and created_by=auth.uid());
drop policy if exists "Teachers update courses" on public.campus_courses;
create policy "Teachers update courses" on public.campus_courses for update to authenticated using(public.campus_is_teacher()) with check(public.campus_is_teacher());
drop policy if exists "Teachers delete courses" on public.campus_courses;
create policy "Teachers delete courses" on public.campus_courses for delete to authenticated using(public.campus_is_teacher());
drop policy if exists "Preview and enrolled lessons visible" on public.campus_lessons;
create policy "Preview and enrolled lessons visible" on public.campus_lessons for select using(is_preview or public.campus_is_teacher() or exists(select 1 from public.campus_enrolments e where e.course_id=campus_lessons.course_id and e.student_id=auth.uid() and e.status='active'));
drop policy if exists "Teachers manage lessons" on public.campus_lessons;
create policy "Teachers manage lessons" on public.campus_lessons for all to authenticated using(public.campus_is_teacher()) with check(public.campus_is_teacher());
drop policy if exists "Users see own enrolments and teacher sees all" on public.campus_enrolments;
create policy "Users see own enrolments and teacher sees all" on public.campus_enrolments for select to authenticated using(student_id=auth.uid() or public.campus_is_teacher());
drop policy if exists "Students request enrolment" on public.campus_enrolments;
create policy "Students request enrolment" on public.campus_enrolments for insert to authenticated with check(student_id=auth.uid() and exists(select 1 from public.campus_courses c where c.id=course_id and c.is_published and ((c.price_eur=0 and status='active') or (c.price_eur>0 and status='pending'))));
drop policy if exists "Students update own progress" on public.campus_enrolments;
create policy "Students update own progress" on public.campus_enrolments for update to authenticated using(student_id=auth.uid() and status='active') with check(student_id=auth.uid() and status='active');
drop policy if exists "Teacher manages enrolments" on public.campus_enrolments;
create policy "Teacher manages enrolments" on public.campus_enrolments for update to authenticated using(public.campus_is_teacher()) with check(public.campus_is_teacher());
drop policy if exists "Students see own certificates and teacher sees all" on public.campus_certificates;
create policy "Students see own certificates and teacher sees all" on public.campus_certificates for select to authenticated using(student_id=auth.uid() or public.campus_is_teacher());
drop policy if exists "Students request own certificates" on public.campus_certificates;
create policy "Students request own certificates" on public.campus_certificates for insert to authenticated with check(student_id=auth.uid() and status='requested' and exists(select 1 from public.campus_enrolments e where e.course_id=campus_certificates.course_id and e.student_id=auth.uid() and e.status='active'));
drop policy if exists "Teacher approves certificates" on public.campus_certificates;
create policy "Teacher approves certificates" on public.campus_certificates for update to authenticated using(public.campus_is_teacher()) with check(public.campus_is_teacher());
-- Restrict student writes to the fields needed for enrolment and progress only.
revoke insert,update on public.campus_enrolments from authenticated;
grant insert(course_id,student_id,status) on public.campus_enrolments to authenticated;
grant update(status,completed_lesson_ids) on public.campus_enrolments to authenticated;
-- IMPORTANT: browser checkout links do not confirm payment. Manually grant access only after verifying payment.
-- For automatic paid enrolment, add a trusted payment provider webhook / server function before launch.
