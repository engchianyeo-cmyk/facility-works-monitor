import { readFileSync } from "node:fs";
import { describe,expect,test,vi } from "vitest";
import { cleanFilename,compensateEvidenceRegistrationFailure,MAX_EVIDENCE_BYTES,SIGNED_ACCESS_SECONDS,validateEvidenceFile,validParent } from "@/lib/evidence";
const read=(path:string)=>readFileSync(new URL(`../${path}`,import.meta.url),"utf8");
const migration=read("supabase/migrations/0016_secure_field_evidence.sql"),route=read("app/api/evidence/route.ts"),access=read("app/api/evidence/[id]/access/route.ts"),panel=read("components/evidence/evidence-panel.tsx");
const file=(name:string,type:string,size:number)=>({name,type,size} as File);
describe("secure field evidence",()=>{
  test("requires authentication for list upload and signed access",()=>{expect(route.match(/AUTHENTICATION_REQUIRED/g)?.length).toBeGreaterThanOrEqual(2);expect(access).toContain("AUTHENTICATION_REQUIRED")});
  test("validates parent record authorization before storage operations",()=>{expect(route).toContain("parentVisible(type,parentId)");expect(route.indexOf("parentVisible(type,parentId)")).toBeLessThan(route.indexOf('storage.from("field-evidence")'))});
  test("lists metadata without exposing storage paths",()=>{expect(route).toContain('select("id,parent_type');expect(route).not.toContain('select("storage_path')});
  test("supports work order and incident evidence",()=>{expect(migration).toContain("parent_type in ('work_order','incident')");expect(panel).toContain("Evidence")});
  test("restricts technicians through parent visibility",()=>{expect(migration).toContain("w.assigned_technician_id=actor_id");expect(migration).toContain("i.assigned_technician_id=actor_id")});
  test("allows authorized supervisor visibility",()=>expect(migration).toContain("('approver','supervisor','administrator')"));
  test("rejects executable types and mismatched content",()=>{expect(validateEvidenceFile(file("bad.exe","application/octet-stream",3),new Uint8Array([1,2,3]))).toMatch(/JPEG/);expect(validateEvidenceFile(file("fake.jpg","image/jpeg",5),new Uint8Array([1,2,3,4,5]))).toMatch(/does not match/)});
  test("rejects oversized files",()=>expect(validateEvidenceFile(file("large.pdf","application/pdf",MAX_EVIDENCE_BYTES+1),new Uint8Array())).toMatch(/10 MB/));
  test("accepts a file exactly at the server size limit",()=>expect(validateEvidenceFile(file("limit.pdf","application/pdf",MAX_EVIDENCE_BYTES),new Uint8Array([37,80,68,70,45]))).toBeNull());
  test("rejects empty files",()=>expect(validateEvidenceFile(file("empty.pdf","application/pdf",0),new Uint8Array())).toMatch(/1 byte/));
  test.each([
    ["executable renamed jpg","attack.jpg","image/jpeg",[77,90,144]],
    ["html renamed pdf","page.pdf","application/pdf",[60,33,68,79,67]],
    ["script renamed png","script.png","image/png",[35,33,47,98,105,110]],
  ])("rejects spoofed signature: %s",(_case,name,type,bytes)=>expect(validateEvidenceFile(file(name,type,bytes.length),new Uint8Array(bytes as number[]))).toMatch(/does not match/));
  test("normalizes hostile filenames",()=>expect(cleanFilename("../../bad<script>.pdf")).toBe("bad_script_.pdf"));
  test("signed access expires after five minutes and validates RLS metadata first",()=>{expect(SIGNED_ACCESS_SECONDS).toBe(300);expect(access.indexOf('from("evidence_items")')).toBeLessThan(access.indexOf("createSignedUrl"))});
  test("creates a metadata and activity event atomically",()=>{expect(migration).toContain("'evidence_uploaded'");expect(migration).toContain("insert into public.activity_logs")});
  test("uses a private bucket with no broad storage object policy",()=>{expect(migration).toContain("'field-evidence','field-evidence',false");expect(migration).not.toMatch(/create\s+policy\s+\S+\s+on\s+storage\.objects/i)});
  test("handles malformed upload and unavailable evidence safely",()=>{expect(route).toContain("MALFORMED_UPLOAD");expect(route).toContain("EVIDENCE_UNAVAILABLE");expect(panel).toContain("temporarily unavailable")});
  test("accepts only valid parent identifiers",()=>{expect(validParent("work_order","10000000-0000-4000-8000-000000000001")).toBe(true);expect(validParent("incident","not-an-id")).toBe(false)});
  test("compensates only the newly generated object after registration failure",()=>{expect(route).toContain('remove([path])');expect(route.indexOf('const cleanup=await compensateEvidenceRegistrationFailure',route.indexOf('if(error||!data?.ok)'))).toBeGreaterThan(route.indexOf('if(error||!data?.ok)'));expect(route).toContain('upsert:false')});
  test("cleanup success removes the new object without reporting an orphan",async()=>{const remove=vi.fn().mockResolvedValue({error:null}),report=vi.fn();await expect(compensateEvidenceRegistrationFailure(remove,{evidenceId:"e",parentType:"work_order",parentId:"p",registrationCode:"DB_FAILED"},report)).resolves.toEqual({orphaned:false});expect(remove).toHaveBeenCalledOnce();expect(report).not.toHaveBeenCalled();expect(route).toContain('return fail(registrationCode,"Evidence could not be registered.",503)')});
  test("cleanup failure is identified for recovery and never reports success",async()=>{const report=vi.fn();await expect(compensateEvidenceRegistrationFailure(async()=>({error:{message:"remove failed"}}),{evidenceId:"e",parentType:"incident",parentId:"p",registrationCode:"DB_FAILED"},report)).resolves.toEqual({orphaned:true});expect(report).toHaveBeenCalledWith("evidence_orphaned_storage_object",expect.objectContaining({cleanupMessage:"remove failed"}));expect(route).toContain('fail("ORPHANED_STORAGE_OBJECT"');expect(route.indexOf('if(error||!data?.ok)')).toBeLessThan(route.indexOf('return NextResponse.json(data,{status:201})'))});
  test("exceptions after upload also enter compensation",()=>{expect(route).toContain('removeNewObject=()=>admin.storage.from("field-evidence").remove([path])');expect(route).toContain('registrationCode:"REGISTRATION_EXCEPTION"');expect(route.indexOf('if(removeNewObject)')).toBeGreaterThan(route.indexOf('}catch{'))});
  test("does not accept a client-controlled storage path",()=>{expect(route).not.toContain('form.get("storage_path")');expect(route).toContain('const path=`evidence/${type.replace("_","-")}/${parentId}/${evidenceId}/${safeName}`')});
  test("database registration constrains the path and requires an existing private object",()=>{expect(migration).toContain("p_storage_path not like 'evidence/'||replace(p_parent_type,'_','-')");expect(migration).toContain("from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path");expect(migration).toContain("'INVALID_STORAGE_OBJECT'")});
  test("guessed evidence IDs remain behind authenticated RLS lookup",()=>{expect(access.indexOf("AUTHENTICATION_REQUIRED")).toBeLessThan(access.indexOf('.from("evidence_items")'));expect(access.indexOf('.from("evidence_items")')).toBeLessThan(access.indexOf("createSignedUrl"));expect(access).toContain('fail("NOT_FOUND"')});
  test("keeps metadata and audit writes in one database function transaction",()=>{expect(migration.indexOf("insert into public.evidence_items")).toBeLessThan(migration.indexOf("insert into public.activity_logs"));expect(migration.indexOf("insert into public.activity_logs")).toBeLessThan(migration.indexOf("return jsonb_build_object('ok',true"))});
});
