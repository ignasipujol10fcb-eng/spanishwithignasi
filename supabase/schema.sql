-- Spanish with Ignasi: initial Supabase schema
-- Run in Supabase SQL Editor. Review policies before launching to paying students.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now()
);
create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Spanish lesson',
  lesson_type text not null check (lesson_type in ('trial','standard')),
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null default 'requested' check (status in ('requested','confirmed','reschedule_requested','cancel_requested','cancelled','completed')),
  notes text not null default '',
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','pending','paid','refunded','not_required')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lesson_positive_duration check (end_at > start_at),
  constraint lesson_duration_by_type check ((lesson_type='trial' and end_at-start_at=interval '30 minutes') or (lesson_type='standard' and end_at-start_at=interval '50 minutes'))
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  constraint no_self_message check (sender_id <> recipient_id)
);
create table if not exists public.lesson_change_requests (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('reschedule','cancellation')),
  request_note text not null,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  created_at timestamptz not null default now()
);
create table if not exists public.availability (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  weekday integer not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  active boolean not null default true,
  constraint availability_positive_duration check (end_time > start_time)
);

-- Prevent overlapping active bookings for the same teacher (including pending requests).
do $ begin
  if not exists (select 1 from pg_constraint where conname='no_overlapping_teacher_lessons') then
    alter table public.lessons add constraint no_overlapping_teacher_lessons
      exclude using gist (teacher_id with =, tstzrange(start_at,end_at,'[)') with &&)
      where (status in ('requested','confirmed','reschedule_requested'));
  end if;
end $;

-- A student may book one active free trial; cancelled trials do not block a new request.
create unique index if not exists one_active_trial_per_student
  on public.lessons(student_id)
  where lesson_type='trial' and status <> 'cancelled';

create index if not exists lessons_student_start_idx on public.lessons(student_id,start_at);
create index if not exists lessons_teacher_start_idx on public.lessons(teacher_id,start_at);
create index if not exists messages_sender_created_idx on public.messages(sender_id,created_at);
create index if not exists messages_recipient_created_idx on public.messages(recipient_id,created_at);
create index if not exists change_requests_lesson_idx on public.lesson_change_requests(lesson_id,created_at desc);

create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='teacher'); $$;

create or replace function public.is_teacher_id(profile_id uuid)
returns boolean language sql stable security definer set search_path=public
as $ select exists(select 1 from public.profiles where id=profile_id and role='teacher'); $;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,full_name,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),'student')
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.lessons enable row level security;
alter table public.messages enable row level security;
alter table public.lesson_change_requests enable row level security;
alter table public.availability enable row level security;

drop policy if exists "Profiles visible to self and teacher" on public.profiles;
create policy "Profiles visible to self and teacher" on public.profiles for select to authenticated using (id=auth.uid() or public.is_teacher());
drop policy if exists "Users update own profile name only" on public.profiles;
-- Restrict browser clients to changing the display name; never allow self-promotion to teacher.
drop policy if exists "Users update own profile name only" on public.profiles;
create policy "Users update own profile name only" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
revoke update on public.profiles from authenticated;
grant update(full_name) on public.profiles to authenticated;
-- IMPORTANT: assign teacher role only from the trusted Supabase SQL editor.

drop policy if exists "Students and teacher read relevant lessons" on public.lessons;
create policy "Students and teacher read relevant lessons" on public.lessons for select to authenticated using(student_id=auth.uid() or teacher_id=auth.uid() or public.is_teacher());
drop policy if exists "Students request own lessons" on public.lessons;
create policy "Students request own lessons" on public.lessons for insert to authenticated with check(student_id=auth.uid() and status='requested' and teacher_id is not null and public.is_teacher_id(teacher_id));
drop policy if exists "Teacher manages lessons" on public.lessons;
create policy "Teacher manages lessons" on public.lessons for update to authenticated using(public.is_teacher()) with check(public.is_teacher());
drop policy if exists "Teacher cancels lessons" on public.lessons;
create policy "Teacher deletes lessons" on public.lessons for delete to authenticated using(public.is_teacher());

drop policy if exists "Participants read messages" on public.messages;
create policy "Participants read messages" on public.messages for select to authenticated using(sender_id=auth.uid() or recipient_id=auth.uid());
drop policy if exists "Send messages between self and teacher" on public.messages;
create policy "Send messages between self and teacher" on public.messages for insert to authenticated with check(sender_id=auth.uid() and sender_id<>recipient_id and ((public.is_teacher() and exists(select 1 from public.profiles p where p.id=recipient_id and p.role='student')) or (not public.is_teacher() and exists(select 1 from public.profiles p where p.id=recipient_id and p.role='teacher'))));
drop policy if exists "Sender can delete own message" on public.messages;
create policy "Sender can delete own message" on public.messages for delete to authenticated using(sender_id=auth.uid());

drop policy if exists "Participants view change requests" on public.lesson_change_requests;
create policy "Participants view change requests" on public.lesson_change_requests for select to authenticated using(public.is_teacher() or requested_by=auth.uid() or exists(select 1 from public.lessons l where l.id=lesson_id and (l.student_id=auth.uid() or l.teacher_id=auth.uid())));
drop policy if exists "Student requests changes to own lessons" on public.lesson_change_requests;
create policy "Student requests changes to own lessons" on public.lesson_change_requests for insert to authenticated with check(requested_by=auth.uid() and exists(select 1 from public.lessons l where l.id=lesson_id and l.student_id=auth.uid()));
drop policy if exists "Teacher resolves change requests" on public.lesson_change_requests;
create policy "Teacher resolves change requests" on public.lesson_change_requests for update to authenticated using(public.is_teacher()) with check(public.is_teacher());

drop policy if exists "Availability is public to signed-in users" on public.availability;
create policy "Availability is public to signed-in users" on public.availability for select to authenticated using(true);
drop policy if exists "Teacher manages own availability" on public.availability;
create policy "Teacher manages own availability" on public.availability for all to authenticated using(public.is_teacher() and teacher_id=auth.uid()) with check(public.is_teacher() and teacher_id=auth.uid());

-- After creating your account, replace the email below with your sign-in email.
-- Run this as project owner to grant teacher role. Never expose service-role credentials.
-- update public.profiles set role='teacher' where id=(select id from auth.users where email='YOUR_EMAIL_HERE');
