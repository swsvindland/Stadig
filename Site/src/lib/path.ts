// The page's path without ".html" (build.format "file") or a trailing slash: "/", "/lift", "/faq".
export const cleanPath = (pathname: string) => pathname.replace(/(\/index)?\.html$/, "").replace(/\/$/, "") || "/";
