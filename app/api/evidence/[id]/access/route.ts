import { NextRequest,NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { SIGNED_ACCESS_SECONDS } from "@/lib/evidence";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
const fail=(code:string,message:string,status:number)=>NextResponse.json({ok:false,code,message},{status});
export async function POST(_request:NextRequest,{params}:{params:Promise<{id:string}>}){
  if(!await getCurrentIdentity())return fail("AUTHENTICATION_REQUIRED","Authentication is required.",401);
  const {id}=await params;const supabase=await createClient();const {data,error}=await supabase.from("evidence_items").select("storage_path").eq("id",id).maybeSingle();
  if(error||!data)return fail("NOT_FOUND","Evidence was not found.",404);
  try{const {data:signed,error:signedError}=await createAdminClient().storage.from("field-evidence").createSignedUrl(data.storage_path,SIGNED_ACCESS_SECONDS);if(signedError||!signed)return fail("ACCESS_FAILED","Evidence access could not be prepared.",503);return NextResponse.json({ok:true,url:signed.signedUrl,expires_in:SIGNED_ACCESS_SECONDS});}
  catch{return fail("ACCESS_FAILED","Evidence access could not be prepared.",503);}
}
