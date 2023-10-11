import type {EventContext} from "@cloudflare/workers-types/2023-07-01"

export async function onRequest(context: EventContext<any, any, any>) {
    const url = new URL(context.request.url);
    const pathname: string = url.pathname;

    // Allow only requests to /rhel/* and /kubernetes/* excluding any requests containing ..
    if (!(pathname.startsWith('/rhel/') || pathname.startsWith('/kubernetes/')) || pathname.includes('..')) {
        return new Response(null, {
            status: 404
        });
    }

    return await context.next()
}
