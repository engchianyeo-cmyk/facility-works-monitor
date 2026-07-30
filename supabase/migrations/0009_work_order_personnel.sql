-- Enforce valid work-order personnel assignments.
begin;

create index if not exists work_orders_assigned_technician_idx
  on public.work_orders (assigned_technician_id)
  where assigned_technician_id is not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.work_orders'::regclass
      and conname = 'work_orders_assigned_technician_profile_fkey'
  ) then
    alter table public.work_orders
      add constraint work_orders_assigned_technician_profile_fkey
      foreign key (assigned_technician_id)
      references public.profiles(id)
      on delete restrict
      not valid;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.work_orders as work_order
    left join public.profiles as profile
      on profile.id = work_order.assigned_technician_id
    where work_order.assigned_technician_id is not null
      and profile.id is null
  ) then
    alter table public.work_orders
      validate constraint work_orders_assigned_technician_profile_fkey;
  else
    raise notice
      'Personnel foreign key remains NOT VALID because legacy assignment references exist';
  end if;
end;
$$;

commit;
