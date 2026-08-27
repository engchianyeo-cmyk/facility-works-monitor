import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import process from "node:process";
import { createClient } from "@supabase/supabase-js";

const root = process.cwd();
const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const npx = process.platform === "win32" ? "npx.cmd" : "npx";
const localProject = "fmworks-local-uat";
const localDatabaseContainer = `supabase_db_${localProject}`;
const baseURL = "http://localhost:3099";
const waitBuffer = new Int32Array(new SharedArrayBuffer(4));

function run(command, args, options = {}) {
  const label = options.label ?? `${command} ${args.join(" ")}`;
  console.log(`\n[release:verify] ${label}`);
  const result = spawnSync(command, args, {
    cwd: root,
    env: options.env ?? process.env,
    input: options.input,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : options.input ? ["pipe", "inherit", "inherit"] : "inherit",
    shell: process.platform === "win32" && command.endsWith(".cmd"),
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (options.capture) process.stderr.write(result.stderr ?? "");
    throw new Error(`${label} failed with exit code ${result.status}`);
  }
  return options.capture ? result.stdout : "";
}

function sql(path, variables = []) {
  const variableArgs = variables.flatMap(([name, value]) => ["-v", `${name}=${value}`]);
  run("docker", ["exec", "-i", localDatabaseContainer, "psql", "-X", "-v", "ON_ERROR_STOP=1", ...variableArgs, "-U", "postgres", "-d", "postgres"], {
    label: `apply ${path}`,
    input: readFileSync(path, "utf8"),
  });
}

function parseSupabaseEnvironment(output) {
  const start = output.indexOf("{");
  if (start >= 0) {
    const parsed = JSON.parse(output.slice(start));
    return parsed;
  }
  return Object.fromEntries(output.split(/\r?\n/).flatMap((line) => {
    const match = line.match(/^([A-Z_]+)="?(.*?)"?$/);
    return match ? [[match[1], match[2]]] : [];
  }));
}

async function seedSyntheticIdentities(environment) {
  const url = environment.API_URL;
  const serviceKey = environment.SERVICE_ROLE_KEY ?? environment.SECRET_KEY;
  if (!url || !serviceKey) throw new Error("Local Supabase did not expose an API URL and service key.");
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const password = "Pilot-Synthetic-2026!";
  const pendingPassword = "Pilot-Pending-2026!";
  const identities = [
    ["administrator", "pilot.admin@example.test", password, "Pilot Administrator"],
    ["supervisor", "pilot.supervisor@example.test", password, "Pilot Supervisor"],
    ["approver", "pilot.approver@example.test", password, "Pilot Approver"],
    ["initiator", "pilot.initiator@example.test", password, "Pilot Initiator"],
    ["technician", "pilot.technician@example.test", password, "Pilot Technician"],
    ["reviewer", "pilot.reviewer@example.test", password, "Pilot Reviewer"],
    ["reviewer", "pilot.pending@example.test", pendingPassword, "Pilot Password Pending"],
  ];
  const created = [];
  for (const [role, email, credential, displayName] of identities) {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: credential,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    });
    if (error || !data.user) throw new Error(`Unable to create synthetic ${role}: ${error?.message ?? "missing user"}`);
    created.push({ role, email, password: credential, displayName, id: data.user.id });
  }
  const values = created.map((identity) =>
    `('${identity.id}'::uuid,'${identity.role}'::text,'${identity.displayName.replaceAll("'", "''")}'::text,${identity.email === "pilot.pending@example.test" ? "true" : "false"})`,
  ).join(",\n");
  const setup = `
begin;
select pg_catalog.set_config('fmworks.profile_admin_rpc','on',true);
update public.profiles as profile
set role = seed.role, display_name = seed.display_name, is_active = true, deleted_at = null
from (values ${values}) as seed(id,role,display_name,password_pending)
where profile.id = seed.id;
  select pg_catalog.set_config('fmworks.profile_admin_rpc','off',true);
select pg_catalog.set_config('fmworks.profile_admin_rpc','on',true);
  select pg_catalog.set_config('fmworks.password_change_completion','on',true);
update public.profiles as profile
set password_change_required = seed.password_pending
from (values ${values}) as seed(id,role,display_name,password_pending)
where profile.id = seed.id;
  select pg_catalog.set_config('fmworks.password_change_completion','off',true);
select pg_catalog.set_config('fmworks.profile_admin_rpc','off',true);
commit;`;
  run("docker", ["exec", "-i", localDatabaseContainer, "psql", "-X", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"], {
    label: "activate synthetic Pilot identities",
    input: setup,
  });
  return {
    E2E_SYNTHETIC_RUN_ID: randomUUID(),
    E2E_ADMIN_EMAIL: "pilot.admin@example.test",
    E2E_ADMIN_PASSWORD: password,
    E2E_SUPERVISOR_EMAIL: "pilot.supervisor@example.test",
    E2E_SUPERVISOR_PASSWORD: password,
    E2E_APPROVER_EMAIL: "pilot.approver@example.test",
    E2E_APPROVER_PASSWORD: password,
    E2E_INITIATOR_EMAIL: "pilot.initiator@example.test",
    E2E_INITIATOR_PASSWORD: password,
    E2E_TECHNICIAN_EMAIL: "pilot.technician@example.test",
    E2E_TECHNICIAN_PASSWORD: password,
    E2E_REVIEWER_EMAIL: "pilot.reviewer@example.test",
    E2E_REVIEWER_PASSWORD: password,
    E2E_PENDING_EMAIL: "pilot.pending@example.test",
    E2E_PENDING_PASSWORD: pendingPassword,
    E2E_PENDING_NEW_PASSWORD: "Pilot-Pending-Private-2026!",
  };
}

function runSqlRegressions() {
  const runners = [
    "tests/sql/run_0020_chain.sh",
    "tests/sql/run_0021_fresh_install.sh",
    "tests/sql/run_0022_uat_material_defect_remediation.sh",
    "tests/sql/run_auth_preserving_fresh_install.sh",
    "tests/sql/run_0023_first_administrator_bootstrap.sh",
    "tests/sql/run_0024_department_master_data_baseline.sh",
    "tests/sql/run_0025_work_order_uat_dataset.sh",
  ];
  for (const runner of runners) {
    const name = `fmworks-release-${runner.match(/run_(.+)\.sh$/)[1].replaceAll("_", "-")}-${process.pid}`;
    try {
      run("docker", ["run", "--name", name, "--tmpfs", "/var/lib/postgresql/data:rw,noexec,nosuid,size=512m", "-e", "POSTGRES_PASSWORD=local-verification-only", "-v", `${root}:/workspace`, "-d", "postgres:15"], { label: `start disposable database for ${runner}` });
      for (let attempt = 0; attempt < 30; attempt += 1) {
        const ready = spawnSync("docker", ["exec", name, "pg_isready", "-U", "postgres"], { stdio: "ignore" });
        if (ready.status === 0) break;
        if (attempt === 29) throw new Error(`Disposable database for ${runner} did not become ready.`);
        Atomics.wait(waitBuffer, 0, 0, 250);
      }
      run("docker", ["exec", name, "sh", `/workspace/${runner}`], { label: `SQL/security regression ${runner}` });
    } finally {
      spawnSync("docker", ["rm", "-f", name], { stdio: "ignore" });
    }
  }
}

async function main() {
  run(npm, ["run", "typecheck"]);
  run(npm, ["run", "lint"]);
  run(npm, ["run", "test"]);
  runSqlRegressions();
  run(npm, ["run", "build"]);
  run(npx, ["supabase", "start"], { label: "start isolated local Supabase" });
  run(npx, ["supabase", "db", "reset", "--local", "--no-seed"], { label: "reset isolated local Supabase" });
  const chain = [
    "supabase/bootstrap/fmworks_pre_0012_bootstrap.sql",
    ...Array.from({ length: 13 }, (_, index) => {
      const number = String(index + 12).padStart(4, "0");
      const matches = [
        "department_management_foundation", "core_work_order_engine", "emergency_incident_management",
        "incident_safe_projection_and_roster_api", "secure_field_evidence", "work_order_completion_rework",
        "asset_registry_foundation", "preventive_maintenance_foundation", "pilot_identity_trust_hardening",
        "fresh_install_trust_contract_repair", "uat_material_defect_remediation", "first_administrator_bootstrap",
        "department_master_data_baseline",
      ];
      return `supabase/migrations/${number}_${matches[index]}.sql`;
    }),
  ];
  for (const path of chain) sql(path);
  const status = run(npx, ["supabase", "status", "-o", "json"], { capture: true, label: "read isolated Supabase test endpoints" });
  const localEnvironment = parseSupabaseEnvironment(status);
  const identities = await seedSyntheticIdentities(localEnvironment);
  sql("supabase/uat/008_work_order_uat_dataset.sql", [["fmworks_preview_project_ref", "pvajuywwwpjlikqjnvgv"]]);
  const env = {
    ...process.env,
    ...identities,
    NEXT_PUBLIC_SUPABASE_URL: localEnvironment.API_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: localEnvironment.ANON_KEY ?? localEnvironment.PUBLISHABLE_KEY,
    SUPABASE_SERVICE_ROLE_KEY: localEnvironment.SERVICE_ROLE_KEY ?? localEnvironment.SECRET_KEY,
    NEXT_PUBLIC_APP_URL: baseURL,
    PLAYWRIGHT_TEST_BASE_URL: baseURL,
    CI: "1",
  };
  run(npx, ["playwright", "test"], { env, label: "authenticated Playwright Pilot acceptance" });
  run("git", ["diff", "--check"], { label: "diff hygiene" });
  console.log("\n[release:verify] PASS -- all release gates completed against isolated/synthetic data.");
}

main().catch((error) => {
  console.error(`\n[release:verify] FAIL -- ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
