import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks=vi.hoisted(()=>({identity:vi.fn(),client:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.identity}));
vi.mock("@/lib/supabase/server",()=>({createClient:mocks.client}));
import { GET, POST } from "@/app/api/work-orders/[id]/release-1/route";
const context={params:Promise.resolve({id:"22222222-2222-4222-8222-222222222222"})};
const url="http://localhost/api/work-orders/order/release-1";
const request=(body:unknown)=>new NextRequest(url,{method:"POST",body:JSON.stringify(body)});
function client(data:unknown=null,error:unknown=null){
  const query={select:vi.fn(),eq:vi.fn(),maybeSingle:vi.fn().mockResolvedValue({data,error})};
  query.select.mockReturnValue(query);query.eq.mockReturnValue(query);
  return {from:vi.fn().mockReturnValue(query),rpc:vi.fn().mockResolvedValue({data:{ok:true},error:null})};
}
beforeEach(()=>{vi.clearAllMocks();mocks.identity.mockResolvedValue({userId:"reviewer",role:"reviewer"});});
describe("Release-1 workspace scope and request boundary",()=>{
  it("does not load child records or privileged RPCs for an invisible Work Order",async()=>{
    const db=client();mocks.client.mockResolvedValue(db);
    expect((await GET(new NextRequest(url),context)).status).toBe(404);
    expect(db.from).toHaveBeenCalledTimes(1);expect(db.from).toHaveBeenCalledWith("work_orders");expect(db.rpc).not.toHaveBeenCalled();
  });
  it("does not dispatch a mutation for an invisible Work Order",async()=>{
    const db=client();mocks.client.mockResolvedValue(db);
    expect((await POST(request({operation:"approve_no_payment",payload:{note:"Attempted approval"}}),context)).status).toBe(404);
    expect(db.rpc).not.toHaveBeenCalled();
  });
  it("keeps authorized operations available through domain RPCs",async()=>{
    mocks.identity.mockResolvedValue({userId:"technician",role:"technician"});
    const db=client({id:"visible"});mocks.client.mockResolvedValue(db);
    expect((await POST(request({operation:"prepare_proposal",payload:{proposed_amount:650}}),context)).status).toBe(200);
    expect(db.rpc).toHaveBeenCalledWith("prepare_work_order_proposal",{p_work_order_id:"22222222-2222-4222-8222-222222222222",p_payload:{proposed_amount:650}});
  });
  it.each(["NaN","Infinity","-Infinity",true,{},[]])("rejects invalid supplied amount %s before database access",async(value)=>{
    expect((await POST(request({operation:"prepare_proposal",payload:{proposed_amount:value}}),context)).status).toBe(400);
    expect(mocks.client).not.toHaveBeenCalled();
  });
  it.each([true,[],"invalid",null])("rejects malformed payload %s",async(payload)=>{
    expect((await POST(request({operation:"prepare_proposal",payload}),context)).status).toBe(400);
  });
  it("denies unauthenticated reads and writes",async()=>{
    mocks.identity.mockResolvedValue(null);
    expect((await GET(new NextRequest(url),context)).status).toBe(401);
    expect((await POST(request({operation:"prepare_proposal",payload:{}}),context)).status).toBe(401);
    expect(mocks.client).not.toHaveBeenCalled();
  });
  it("contains transport exceptions without exposing private error details",async()=>{
    mocks.client.mockRejectedValue(new Error("private database credential"));
    for (const response of [await GET(new NextRequest(url),context),await POST(request({operation:"approve_no_payment",payload:{note:"Approval"}}),context)]) {
      expect(response.status).toBe(500);expect(JSON.stringify(await response.json())).not.toContain("private database credential");
    }
  });
});
