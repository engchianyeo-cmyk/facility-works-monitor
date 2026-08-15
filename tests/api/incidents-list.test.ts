import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks=vi.hoisted(()=>({getCurrentIdentity:vi.fn(),createClient:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.getCurrentIdentity}));
vi.mock("@/lib/supabase/server",()=>({createClient:mocks.createClient}));
import { GET } from "@/app/api/incidents/route";

const identity={userId:"11111111-1111-4111-8111-111111111111",email:"tech@example.com",displayName:"Tech",department:"Facilities",role:"technician" as const};
// Fluent Supabase test double intentionally models changing builder generics.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function builder(result:{data:unknown[];error:unknown;count:number}){const chain:any={};for(const method of ["select","eq","neq","not","in","is","or","order"])chain[method]=vi.fn(()=>chain);chain.then=(resolve:(value:unknown)=>unknown)=>Promise.resolve(result).then(resolve);return chain;}
beforeEach(()=>{vi.clearAllMocks();mocks.getCurrentIdentity.mockResolvedValue(identity);});
describe("GET /api/incidents",()=>{
  test("denies unauthenticated callers",async()=>{mocks.getCurrentIdentity.mockResolvedValue(null);expect((await GET(new NextRequest("http://localhost/api/incidents"))).status).toBe(401)});
  test("paginates filtered incidents and leaves Technician visibility to RLS",async()=>{const query=builder({data:[{id:"1",status:"reported"}],error:null,count:1});mocks.createClient.mockResolvedValue({from:vi.fn(()=>query)});const response=await GET(new NextRequest("http://localhost/api/incidents?status=reported&severity=emergency&page=1&page_size=10&assigned_responder=mine"));expect(response.status).toBe(200);expect(await response.json()).toMatchObject({data:[{id:"1"}],pagination:{page:1,page_size:10,total:1,total_pages:1}});expect(query.eq).toHaveBeenCalledWith("assigned_technician_id",identity.userId);});
  test("orders active emergencies before other active and terminal records",async()=>{const queues=[builder({data:[{id:"emergency"}],error:null,count:1}),builder({data:[{id:"active"}],error:null,count:1}),builder({data:[{id:"closed"}],error:null,count:1})];mocks.createClient.mockResolvedValue({from:vi.fn(()=>queues.shift())});const response=await GET(new NextRequest("http://localhost/api/incidents"));expect((await response.json()).data.map((x:{id:string})=>x.id)).toEqual(["emergency","active","closed"]);});
  test("returns a safe database transport failure",async()=>{const query=builder({data:[],error:{message:"private SQL"},count:0});mocks.createClient.mockResolvedValue({from:vi.fn(()=>query)});const response=await GET(new NextRequest("http://localhost/api/incidents?status=reported"));expect(response.status).toBe(500);expect(await response.json()).toEqual({ok:false,code:"INTERNAL_ERROR",message:"Unable to list the emergency incident.",error:"Unable to list the emergency incident."});});
});
