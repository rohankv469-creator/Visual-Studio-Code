create type public.queue_status as enum ('waiting', 'serving', 'served', 'skipped', 'cancelled');
create type public.prediction_state as enum ('on_schedule', 'slight_delay', 'significant_delay');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  role text not null default 'student' check (role in ('student', 'staff', 'admin')),
  language text not null default 'en' check (language in ('en', 'ta')),
  notification_preferences jsonb not null default '{"position":true,"wait":true,"turn":true}'::jsonb,
  created_at timestamptz not null default now()
);
create table public.services (
  id uuid primary key default gen_random_uuid(), name_en text not null, name_ta text not null,
  average_service_minutes int not null default 7, active_counters int not null default 1,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table public.queues (
  id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id),
  queue_date date not null default current_date, current_number int not null default 0,
  next_number int not null default 1, is_paused boolean not null default false,
  updated_at timestamptz not null default now(), unique(service_id, queue_date)
);
create table public.queue_tickets (
  id uuid primary key default gen_random_uuid(), queue_id uuid not null references public.queues(id),
  user_id uuid not null references public.profiles(id), ticket_code text not null unique,
  sequence_number int not null, status public.queue_status not null default 'waiting',
  checked_in_at timestamptz, served_at timestamptz, created_at timestamptz not null default now()
);
create table public.queue_events (
  id bigint generated always as identity primary key, queue_id uuid not null references public.queues(id),
  ticket_id uuid references public.queue_tickets(id), event_type text not null,
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
  ticket_id uuid references public.queue_tickets(id), title_en text not null, title_ta text not null,
  body_en text not null, body_ta text not null, read_at timestamptz, created_at timestamptz not null default now()
);
create table public.ai_predictions (
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references public.queue_tickets(id),
  state public.prediction_state not null, current_minutes int not null, predicted_minutes int not null,
  confidence numeric(5,2) not null, explanation_en text not null, explanation_ta text not null,
  created_at timestamptz not null default now()
);
create table public.staff (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  staff_code text unique not null, counter_name text, is_on_duty boolean not null default true
);
create table public.queue_history (
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null unique references public.queue_tickets(id),
  waiting_minutes int not null, completion_time timestamptz, created_at timestamptz not null default now()
);

alter table public.queues enable row level security;
alter table public.queue_tickets enable row level security;
alter table public.notifications enable row level security;
create policy "students read active queues" on public.queues for select using (true);
create policy "students read own tickets" on public.queue_tickets for select using (auth.uid() = user_id);
create policy "students read own notifications" on public.notifications for select using (auth.uid() = user_id);

-- Realtime publication: queue state changes update student screens without refresh.
alter publication supabase_realtime add table public.queues, public.queue_tickets, public.notifications, public.ai_predictions;
