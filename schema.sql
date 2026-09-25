-- MANCHESTER FC — Supabase schema
-- Ejecutar primero en SQL Editor.

create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('organizer','coach_male','coach_female','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.branch_type as enum ('masculino','femenino');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ledger_type as enum ('income','expense','advance','refund');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'viewer',
  created_at timestamptz not null default now()
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  dni text unique,
  pin_hash text,
  full_name text not null,
  branch public.branch_type not null,
  phone text,
  jersey_number integer,
  active boolean not null default true,
  current_debt numeric(12,2) not null default 0 check (current_debt >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_dni check (dni is null or dni ~ '^[0-9]{7,9}$')
);

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  season text not null,
  branch public.branch_type not null,
  division text,
  format text not null default 'round_robin',
  direct_promotions integer not null default 0,
  has_playoffs boolean not null default false,
  venue_cost numeric(12,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(name, season, branch, division)
);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid references public.tournaments(id) on delete set null,
  branch public.branch_type not null,
  match_date date not null,
  opponent text not null,
  stage text not null default 'regular',
  goals_for integer not null default 0,
  goals_against integer not null default 0,
  venue text,
  venue_cost numeric(12,2) not null default 0,
  payer_count integer,
  closed boolean not null default false,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.match_players (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  played boolean not null default true,
  starter boolean not null default false,
  goals integer not null default 0 check (goals >= 0),
  assists integer not null default 0 check (assists >= 0),
  yellow_cards integer not null default 0 check (yellow_cards >= 0),
  red_cards integer not null default 0 check (red_cards >= 0),
  amount_due numeric(12,2) not null default 0,
  amount_paid numeric(12,2) not null default 0,
  unique(match_id, player_id)
);

create table if not exists public.ledger (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references public.players(id) on delete set null,
  match_id uuid references public.matches(id) on delete set null,
  entry_date date not null default current_date,
  type public.ledger_type not null,
  category text not null,
  description text,
  amount numeric(12,2) not null check(amount >= 0),
  payment_method text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.fundraising_events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  event_type text not null check (event_type in ('raffle','party','tickets','sponsor','other')),
  event_date date,
  goal_amount numeric(12,2) not null default 0,
  raised_amount numeric(12,2) not null default 0,
  expenses_amount numeric(12,2) not null default 0,
  distribution_rule text not null default 'none',
  debt_offset_enabled boolean not null default false,
  status text not null default 'open',
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.fundraising_assignments (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.fundraising_events(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  assigned_units integer not null default 0,
  sold_units integer not null default 0,
  collected_amount numeric(12,2) not null default 0,
  pending_amount numeric(12,2) not null default 0,
  credit_generated numeric(12,2) not null default 0,
  unique(event_id, player_id)
);

-- Historial agregado por torneo. Sirve para importar torneos viejos sin recrear cada partido.
create table if not exists public.player_tournament_history (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  tournament_name text not null,
  season text not null,
  division text,
  appearances integer not null default 0,
  goals integer not null default 0,
  yellow_cards integer not null default 0,
  red_cards integer not null default 0,
  provisional boolean not null default false,
  source_note text,
  unique(player_id, tournament_name, season, division)
);

create or replace view public.player_goal_history as
select
  p.id as player_id,
  p.full_name,
  p.branch,
  h.tournament_name,
  h.season,
  h.division,
  h.appearances,
  h.goals,
  h.yellow_cards,
  h.red_cards,
  h.provisional,
  sum(case when h.provisional = false then h.goals else 0 end)
    over(partition by p.id) as verified_goals_total,
  sum(h.goals) over(partition by p.id) as raw_goals_total
from public.players p
join public.player_tournament_history h on h.player_id=p.id;

create or replace function public.current_role()
returns public.app_role
language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid() $$;

create or replace function public.can_manage_sports(p_branch public.branch_type)
returns boolean
language sql stable security definer set search_path=public
as $$
select coalesce(
  public.current_role()='organizer'
  or (public.current_role()='coach_male' and p_branch='masculino')
  or (public.current_role()='coach_female' and p_branch='femenino'),
false)
$$;

create or replace function public.player_self_lookup(p_dni text,p_pin text)
returns table(full_name text,branch public.branch_type,current_debt numeric,matches_played bigint,goals bigint,yellow_cards bigint,red_cards bigint)
language sql security definer set search_path=public
as $$
select p.full_name,p.branch,p.current_debt,
       count(mp.id) filter(where mp.played),
       coalesce(sum(mp.goals),0),coalesce(sum(mp.yellow_cards),0),coalesce(sum(mp.red_cards),0)
from public.players p
left join public.match_players mp on mp.player_id=p.id
where p.dni=regexp_replace(p_dni,'\D','','g')
  and p.pin_hash is not null
  and p.pin_hash=crypt(p_pin,p.pin_hash)
group by p.id;
$$;
grant execute on function public.player_self_lookup(text,text) to anon, authenticated;

create or replace function public.set_player_pin(p_player_id uuid,p_pin text)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if public.current_role()<>'organizer' then raise exception 'Sin permiso'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN inválido'; end if;
  update public.players set pin_hash=crypt(p_pin,gen_salt('bf')),updated_at=now() where id=p_player_id;
end $$;
grant execute on function public.set_player_pin(uuid,text) to authenticated;

create or replace function public.register_player_payment(p_player_id uuid,p_amount numeric,p_category text default 'Pago jugador',p_method text default null,p_description text default null)
returns numeric language plpgsql security definer set search_path=public
as $$
declare new_debt numeric(12,2);
begin
  if public.current_role()<>'organizer' then raise exception 'Sin permiso'; end if;
  if p_amount<=0 then raise exception 'Monto inválido'; end if;
  update public.players set current_debt=greatest(current_debt-p_amount,0),updated_at=now()
  where id=p_player_id returning current_debt into new_debt;
  insert into public.ledger(player_id,type,category,description,amount,payment_method,created_by)
  values(p_player_id,'income',p_category,p_description,p_amount,p_method,auth.uid());
  return new_debt;
end $$;
grant execute on function public.register_player_payment(uuid,numeric,text,text,text) to authenticated;

create or replace function public.close_match(p_match_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare m public.matches; cnt integer; each_due numeric(12,2);
begin
  select * into m from public.matches where id=p_match_id for update;
  if m.id is null then raise exception 'Partido inexistente'; end if;
  if not public.can_manage_sports(m.branch) then raise exception 'Sin permiso'; end if;
  if m.closed then return; end if;
  select count(*) into cnt from public.match_players where match_id=p_match_id and played=true;
  if cnt>0 and m.venue_cost>0 then
    each_due:=round(m.venue_cost/cnt,2);
    update public.match_players set amount_due=each_due where match_id=p_match_id and played=true;
    update public.players p
    set current_debt=current_debt+greatest(mp.amount_due-mp.amount_paid,0),updated_at=now()
    from public.match_players mp
    where mp.match_id=p_match_id and mp.played=true and p.id=mp.player_id;
  end if;
  update public.matches set closed=true,payer_count=cnt where id=p_match_id;
end $$;
grant execute on function public.close_match(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.players enable row level security;
alter table public.tournaments enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.ledger enable row level security;
alter table public.fundraising_events enable row level security;
alter table public.fundraising_assignments enable row level security;
alter table public.player_tournament_history enable row level security;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.current_role()='organizer');

drop policy if exists players_staff_read on public.players;
create policy players_staff_read on public.players for select to authenticated using(
 public.current_role()='organizer'
 or (public.current_role()='coach_male' and branch='masculino')
 or (public.current_role()='coach_female' and branch='femenino')
);

drop policy if exists players_org_write on public.players;
create policy players_org_write on public.players for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');

drop policy if exists tournaments_read on public.tournaments;
create policy tournaments_read on public.tournaments for select to authenticated using(public.current_role() is not null);
drop policy if exists tournaments_write on public.tournaments;
create policy tournaments_write on public.tournaments for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');

drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select to authenticated using(public.current_role() is not null);
drop policy if exists matches_write on public.matches;
create policy matches_write on public.matches for all to authenticated
using(public.can_manage_sports(branch)) with check(public.can_manage_sports(branch));

drop policy if exists match_players_read on public.match_players;
create policy match_players_read on public.match_players for select to authenticated using(
 exists(select 1 from public.matches m where m.id=match_id and public.can_manage_sports(m.branch))
);
drop policy if exists match_players_write on public.match_players;
create policy match_players_write on public.match_players for all to authenticated
using(exists(select 1 from public.matches m where m.id=match_id and public.can_manage_sports(m.branch)))
with check(exists(select 1 from public.matches m where m.id=match_id and public.can_manage_sports(m.branch)));

drop policy if exists ledger_org on public.ledger;
create policy ledger_org on public.ledger for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');

drop policy if exists events_read on public.fundraising_events;
create policy events_read on public.fundraising_events for select to authenticated using(public.current_role() is not null);
drop policy if exists events_write on public.fundraising_events;
create policy events_write on public.fundraising_events for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');

drop policy if exists assignments_org on public.fundraising_assignments;
create policy assignments_org on public.fundraising_assignments for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');

drop policy if exists history_read on public.player_tournament_history;
create policy history_read on public.player_tournament_history for select to authenticated using(public.current_role() is not null);
drop policy if exists history_write on public.player_tournament_history;
create policy history_write on public.player_tournament_history for all to authenticated
using(public.current_role()='organizer') with check(public.current_role()='organizer');
