export type Known<T> = T | "UNKNOWN";
export type OperatingModel = "IN_HOUSE" | "OUTSOURCED" | "HYBRID";
export type StaffingRole = { role:string; recommendedFte:number; coverage:string; competency:string; reason:string; workloadBasis:string; slaBasis:string; assumptions:string[]; confidence:number; gaps:string[] };
export type StaffingInput = { operatingModel:OperatingModel; operatingHours:Known<number>; shiftsPerDay:Known<number>; assetCount:Known<number>; criticalAssetCount:Known<number>; emergencyCoverage:Known<boolean>; proposedOrganization?:Array<{role:string;fte:number;coverage?:string;competency?:string}>; escalationRoles?:string[] };
export type StaffingAnalysis = { advisoryOnly:true; roles:StaffingRole[]; unknownInputs:string[]; coverageGaps:string[]; modelObservations:string[] };

export function analyseStaffingDeterministically(input: StaffingInput): StaffingAnalysis {
  const unknownInputs=Object.entries(input).filter(([,v])=>v==="UNKNOWN").map(([k])=>k);
  const shifts=input.shiftsPerDay==="UNKNOWN"?1:input.shiftsPerDay;
  const assets=input.assetCount==="UNKNOWN"?0:input.assetCount;
  const technicalFte=Math.max(1,Math.ceil(assets/80),shifts);
  const required=[
    {role:"Facility Manager",fte:1,competency:"Facilities governance and contract accountability"},
    {role:"Facilities Engineer",fte:1,competency:"Engineering and statutory coordination"},
    {role:"Maintenance Supervisor",fte:shifts,competency:"On-duty escalation and safe-work supervision"},
    {role:"Mechanical/HVAC Technician",fte:technicalFte,competency:"Mechanical/HVAC trade competency"},
    {role:"Electrical Technician",fte:technicalFte,competency:"Qualified electrical competency"},
    {role:"Building/Plumbing Technician",fte:Math.max(1,Math.ceil(assets/120)),competency:"Building fabric and plumbing competency"},
    {role:"Maintenance Coordinator/Helpdesk",fte:shifts,competency:"Work control and SLA acknowledgement"},
    {role:"Specialist Contractors",fte:1,competency:"Licensed specialist coverage as required"},
  ];
  const proposed=new Map((input.proposedOrganization??[]).map(x=>[x.role.toLowerCase(),x]));
  const coverageGaps:string[]=[];
  const roles=required.map(r=>{const current=proposed.get(r.role.toLowerCase());const gaps:string[]=[];if(input.operatingModel!=="IN_HOUSE"&&(!current||current.fte<r.fte))gaps.push(`FTE gap: ${Math.max(0,r.fte-(current?.fte??0))}`);if(r.role==="Maintenance Supervisor"&&input.emergencyCoverage===true&&(!current||!current.coverage?.toLowerCase().includes("night")))gaps.push("Night-shift Supervisor coverage gap");if(current&&!current.competency)gaps.push("Competency evidence missing");coverageGaps.push(...gaps.map(g=>`${r.role}: ${g}`));return{role:r.role,recommendedFte:r.fte,coverage:r.role.includes("Supervisor")||r.role.includes("Coordinator")?`${shifts} shift(s)/day`:"Day coverage plus governed standby",competency:r.competency,reason:"Capacity and escalation coverage required for approved SLA delivery.",workloadBasis:input.assetCount==="UNKNOWN"?"UNKNOWN asset workload":`${assets} assets`,slaBasis:"Approved response, attendance, rectification and escalation obligations",assumptions:["Deterministic planning baseline; validate with task-level workload study"],confidence:unknownInputs.length?0.55:0.8,gaps};});
  for(const role of input.escalationRoles??[])if(!required.some(r=>r.role.toLowerCase().includes(role.toLowerCase().replace("facilities ",""))))coverageGaps.push(`Escalation hierarchy gap: ${role}`);
  return{advisoryOnly:true,roles,unknownInputs,coverageGaps,modelObservations:[`${input.operatingModel} responsibilities must be confirmed by management.`,`Missing facts remain UNKNOWN: ${unknownInputs.join(", ")||"none"}.`]};
}

export function validateCommentaryNumbers(narrative:string,metrics:Readonly<Record<string,number|string|null>>){const supplied=new Set(Object.values(metrics).filter((v):v is number=>typeof v==="number").flatMap(v=>[String(v),String(Math.round(v))]));return[...narrative.matchAll(/\b\d+(?:\.\d+)?\b/g)].every(m=>supplied.has(m[0]));}
