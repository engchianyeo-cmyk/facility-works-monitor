#!/bin/sh
set -eu
PSQL="psql -X -v ON_ERROR_STOP=1 -U postgres -d ${TEST_DATABASE:-postgres}"
$PSQL -f /workspace/tests/sql/0021_supabase_managed_prerequisite.sql
$PSQL -f /workspace/supabase/bootstrap/fmworks_pre_0012_bootstrap.sql
for number in 0012 0013 0014 0015 0016 0017 0018 0019 0020 0021 0022 0023 0024; do
  migration=$(find /workspace/supabase/migrations -maxdepth 1 -name "${number}_*.sql" | head -n 1)
  $PSQL -f "$migration"
done
$PSQL -c "insert into auth.users(id,email,raw_user_meta_data) values('25000000-0000-4000-8000-000000000001','go008-admin@example.test','{\"display_name\":\"GO008 Administrator\"}'::jsonb); set fmworks.profile_admin_rpc='on'; update public.profiles set role='administrator',is_active=true,deleted_at=null,password_change_required=false where id='25000000-0000-4000-8000-000000000001'; reset fmworks.profile_admin_rpc;"
$PSQL -f /workspace/supabase/uat/008_work_order_uat_dataset.sql
$PSQL -f /workspace/tests/sql/0025_work_order_uat_dataset.test.sql
