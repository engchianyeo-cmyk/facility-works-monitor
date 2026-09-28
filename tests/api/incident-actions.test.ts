import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks=vi.hoisted(()=>({getCurrentIdentity:vi.fn(),createClient:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.getCurrentIdentity}));vi.mock("@/lib/supabase/server",()=>({createClient:mocks.createClient}));
import { POST as acknowledge } from "@/app/api/incidents/[id]/acknowledge/route";
import { POST as phase } from "@/app/api/incidents/[id]/phase/route";
import { POST as close } from "@/app/api/incidents/[id]/close/route";
const context={params:Promise.resolve({id:"incident-id"})};
beforeEach(()=>{vi.clearAllMocks();mocks.getCurrentIdentity.mockResolvedValue({userId:"tech",role:"technician"});});
describe("incident action APIs",()=>{
  test("assigned Technician acknowledgement delegates to database",async()=>{const rpc=vi.fn().mockResolvedValue({data:{ok:true,incident:{status:"acknowledged"}},error:null});mocks.createClient.mockResolvedValue({rpc});expect((await acknowledge(new NextRequest("http://localhost/ack"),context)).status).toBe(200);expect(rpc).toHaveBeenCalledWith("transition_incident",{p_incident_id:"incident-id",p_action:"acknowledge"});});
  test("unrelated Technician database denial maps to 403",async()=>{mocks.createClient.mockResolvedValue({rpc:vi.fn().mockResolvedValue({data:{ok:false,code:"ACCESS_DENIED",message:"You cannot update this incident."},error:null})});expect((await acknowledge(new NextRequest("http://localhost/ack"),context)).status).toBe(403);});
  test("valid phase maps to approved database action",async()=>{const rpc=vi.fn().mockResolvedValue({data:{ok:true,incident:{status:"on_site"}},error:null});mocks.createClient.mockResolvedValue({rpc});const response=await phase(new NextRequest("http://localhost/phase",{method:"POST",body:JSON.stringify({phase:"on_site"})}),context);expect(response.status).toBe(200);expect(rpc).toHaveBeenCalledWith("transition_incident",{p_incident_id:"incident-id",p_action:"arrive"});});
  test("invalid phase is rejected before database call",async()=>{const response=await phase(new NextRequest("http://localhost/phase",{method:"POST",body:JSON.stringify({phase:"teleported"})}),context);expect(response.status).toBe(400);expect(mocks.createClient).not.toHaveBeenCalled();});
  test("database rejects out-of-sequence phase",async()=>{mocks.createClient.mockResolvedValue({rpc:vi.fn().mockResolvedValue({data:{ok:false,code:"INVALID_TRANSITION",message:"Not allowed."},error:null})});expect((await phase(new NextRequest("http://localhost/phase",{method:"POST",body:JSON.stringify({phase:"safe"})}),context)).status).toBe(409);});
  test("closure authorization remains database-authoritative",async()=>{mocks.createClient.mockResolvedValue({rpc:vi.fn().mockResolvedValue({data:{ok:false,code:"ACCESS_DENIED",message:"Denied."},error:null})});expect((await close(new NextRequest("http://localhost/close",{method:"POST",body:"{}"}),context)).status).toBe(403);});
  test("permitted closure delegates to the database close action",async()=>{mocks.getCurrentIdentity.mockResolvedValue({userId:"admin",role:"administrator"});const rpc=vi.fn().mockResolvedValue({data:{ok:true,incident:{status:"closed"}},error:null});mocks.createClient.mockResolvedValue({rpc});expect((await close(new NextRequest("http://localhost/close",{method:"POST",body:JSON.stringify({closure_notes:"Recovery complete"})}),context)).status).toBe(200);expect(rpc).toHaveBeenCalledWith("transition_incident",{p_incident_id:"incident-id",p_action:"close"});});
});
