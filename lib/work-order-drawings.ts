export type WorkOrderDrawing = {
  code: string;
  title: string;
  src: string;
  alt: string;
  width: number;
  height: number;
};

export const WORK_ORDER_DRAWINGS: readonly WorkOrderDrawing[] = [
  {
    code: "FW-001",
    title: "Site Plot Plan, Perspective, 1st Storey and Utility Block Layout",
    src: "/work-order-drawings/FW-001.png",
    alt: "FW-001 Site Plot Plan, Perspective, 1st Storey and Utility Block Layout",
    width: 1066,
    height: 682,
  },
  {
    code: "FW-002",
    title: "2nd Storey Plan",
    src: "/work-order-drawings/FW-002.png",
    alt: "FW-002 2nd Storey Plan",
    width: 1024,
    height: 742,
  },
  {
    code: "FW-003",
    title: "Roof Plan",
    src: "/work-order-drawings/FW-003.png",
    alt: "FW-003 Roof Plan",
    width: 1024,
    height: 742,
  },
  {
    code: "FW-004",
    title: "North, South, East and West Elevations",
    src: "/work-order-drawings/FW-004.png",
    alt: "FW-004 North, South, East and West Elevations",
    width: 1024,
    height: 742,
  },
];
