import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
const mocks=vi.hoisted(()=>({identity:vi.fn(),rpc:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.identity}));
vi.mock("@/lib/supabase/server",()=>({createClient:async()=>({rpc:mocks.rpc})}));
import { POST } from "@/app/api/admin/contractors/route";
const request=(body:unknown)=>new NextRequest("http://localhost/api/admin/contractors",{method:"POST",body:JSON.stringify(body)});
beforeEach(()=>{vi.clearAllMocks();mocks.identity.mockResolvedValue({role:"administrator"});mocks.rpc.mockResolvedValue({data:{ok:true},error:null});});
describe("audited contractor administration",()=>{
 it("denies unauthenticated requests",async()=>{mocks.identity.mockResolvedValue(null);expect((await POST(request({kind:"vendor"}))).status).toBe(401);expect(mocks.rpc).not.toHaveBeenCalled();});
 it.each(["reviewer","initiator","approver","technician"])("denies %s",async role=>{mocks.identity.mockResolvedValue({role});expect((await POST(request({kind:"vendor"}))).status).toBe(403);expect(mocks.rpc).not.toHaveBeenCalled();});
 it.each(["supervisor","facility_manager","administrator"])("routes %s writes through audited RPC",async role=>{mocks.identity.mockResolvedValue({role});const body={kind:"vendor",name:"Synthetic contractor"};expect((await POST(request(body))).status).toBe(200);expect(mocks.rpc).toHaveBeenCalledWith("create_contractor_master",{p_payload:body});});
 it("maps overlapping rate periods to HTTP 409",async()=>{mocks.rpc.mockResolvedValue({data:{ok:false,code:"RATE_PERIOD_OVERLAP",message:"Rate period overlaps"},error:null});expect((await POST(request({kind:"rate"}))).status).toBe(409);});
 it("does not expose database transport errors",async()=>{mocks.rpc.mockResolvedValue({data:null,error:{message:"private details"}});const response=await POST(request({kind:"vendor"}));expect(response.status).toBe(503);expect(JSON.stringify(await response.json())).not.toContain("private details");});
});
