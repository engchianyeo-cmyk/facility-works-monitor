import { beforeEach, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks=vi.hoisted(()=>({identity:vi.fn(),client:vi.fn(),admin:vi.fn(),upload:vi.fn(),remove:vi.fn(),rpc:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.identity}));
vi.mock("@/lib/supabase/server",()=>({createClient:mocks.client}));
vi.mock("@/lib/supabase/admin",()=>({createAdminClient:mocks.admin}));
import { POST } from "@/app/api/work-orders/[id]/commercial-documents/route";
const id="11111111-1111-4111-8111-111111111111";
const recordId="22222222-2222-4222-8222-222222222222";
let order:Record<string,unknown>|null;
let record:Record<string,unknown>|null;
function request(size=5){const form=new FormData();form.set("document_type","quotation");form.set("record_id",recordId);form.set("file",new File([size===5?"%PDF-":new Uint8Array(size)],"quote.pdf",{type:"application/pdf"}));return new NextRequest("http://localhost/upload",{method:"POST",body:form});}
const context=()=>({params:Promise.resolve({id})});
beforeEach(()=>{
 vi.clearAllMocks();order={id,status:"assigned",assigned_technician_id:"owner",facility_id:"facility"};record={id:recordId,status:"draft"};
 mocks.identity.mockResolvedValue({role:"technician",userId:"owner"});
 mocks.rpc.mockImplementation(async(name:string)=>name==="technician_facility_read_permitted"?{data:true,error:null}:{data:{ok:true},error:null});
 mocks.client.mockResolvedValue({rpc:mocks.rpc,from:(table:string)=>{const query={select:()=>query,eq:()=>query,maybeSingle:async()=>({data:table==="work_orders"?order:record,error:null})};return query;}});
 mocks.upload.mockResolvedValue({error:null});mocks.remove.mockResolvedValue({error:null});mocks.admin.mockReturnValue({storage:{from:()=>({upload:mocks.upload,remove:mocks.remove})}});
});
test("denies hidden Work Order before privileged upload",async()=>{order=null;expect((await POST(request(),context())).status).toBe(404);expect(mocks.admin).not.toHaveBeenCalled();});
test.each(["reviewer","initiator","approver"])("denies %s before privileged upload",async(role)=>{mocks.identity.mockResolvedValue({role,userId:"owner"});expect((await POST(request(),context())).status).toBe(403);expect(mocks.admin).not.toHaveBeenCalled();});
test("denies unassigned Technician before privileged upload",async()=>{mocks.identity.mockResolvedValue({role:"technician",userId:"other"});expect((await POST(request(),context())).status).toBe(403);expect(mocks.admin).not.toHaveBeenCalled();});
test("denies immutable quotation before privileged upload",async()=>{record={id:recordId,status:"approved"};expect((await POST(request(),context())).status).toBe(403);expect(mocks.admin).not.toHaveBeenCalled();});
test("rejects oversized commercial documents before database and storage",async()=>{expect((await POST(request(10*1024*1024+1),context())).status).toBe(400);expect(mocks.client).not.toHaveBeenCalled();expect(mocks.admin).not.toHaveBeenCalled();});
test("registers authorized upload and retains RPC authority",async()=>{expect((await POST(request(),context())).status).toBe(201);expect(mocks.upload).toHaveBeenCalledOnce();expect(mocks.rpc).toHaveBeenCalledWith("register_work_order_commercial_document",expect.objectContaining({p_work_order_id:id,p_record_id:recordId}));});
test("reports cleanup failures after rejected registration",async()=>{mocks.rpc.mockImplementation(async(name:string)=>name==="technician_facility_read_permitted"?{data:true,error:null}:{data:{ok:false,code:"ACCESS_DENIED"},error:null});mocks.remove.mockResolvedValue({error:{message:"failed"}});const response=await POST(request(),context());expect(response.status).toBe(503);expect((await response.json()).code).toBe("ORPHANED_STORAGE_OBJECT");expect(mocks.remove).toHaveBeenCalledOnce();});
test("reports cleanup exceptions after registration exceptions",async()=>{mocks.rpc.mockImplementation(async(name:string)=>{if(name==="technician_facility_read_permitted")return {data:true,error:null};throw new Error("RPC failed");});mocks.remove.mockRejectedValue(new Error("remove failed"));const response=await POST(request(),context());expect(response.status).toBe(503);expect((await response.json()).code).toBe("ORPHANED_STORAGE_OBJECT");});
