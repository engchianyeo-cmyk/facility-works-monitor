import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  try {
    const body = await request.json();

    const supabase = await createClient();

    const { data, error } = await supabase
      .from("work_orders")
      .insert({
        title: body.title,
        location: body.location,
        category_id: body.category_id || null,
        priority: body.priority,
        description: body.description,
        submitted_by: body.submitted_by,
        status: "submitted",
      })
      .select()
      .single();

    if (error) {
      console.error(error);
      return NextResponse.json(
        { error: error.message },
        { status: 400 }
      );
    }

    return NextResponse.json(
      { data },
      { status: 201 }
    );
  } catch (err) {
    console.error(err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
