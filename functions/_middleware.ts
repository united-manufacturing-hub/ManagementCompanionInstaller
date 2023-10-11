import type {EventContext} from "@cloudflare/workers-types/2023-07-01"

export async function onRequest(context: EventContext<any, any, any>) {
    const url = new URL(context.request.url);
    const pathname: string = url.pathname;
    if (pathname.split('/').some(segment => segment.startsWith('.'))) {
        return new Response(null, {
            status: 404
        });
    }
    // Block access to self
    if (pathname.indexOf("_middleware.ts") > 0){
        return new Response(null, {
            status: 404
        });
    }
    return await context.next()
}
