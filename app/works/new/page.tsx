import { createClient } from "@/lib/supabase/server";
import NewWorkOrderForm from "./form";

export default async function NewWorkOrderPage() {
  const supabase = await createClient();
  const { data: categories } = await supabase.from("categories").select("id, name").order("name");

  return (
    <main className="max-w-xl mx-auto p-8">
      <h1 className="text-2xl font-bold tracking-tight mb-6">Submit Work Order</h1>
      <NewWorkOrderForm categories={categories ?? []} />
    </main>
  );
}
