export const getApiUrl = () => {
  if (process.env.NEXT_PUBLIC_API_URL) {
    const url = process.env.NEXT_PUBLIC_API_URL.replace(/\/+$/, "").replace(/\/api$/, "")
    return url.match(/^https?:\/\/|^\/\//) ? url : `https://${url}`
  }

  if (typeof window !== "undefined") {
    const { protocol, hostname } = window.location
    const port =
      hostname === "localhost" || hostname === "127.0.0.1" || hostname === "192.168.1.5"
        ? ":5000"
        : ""
    return `${protocol}//${hostname}${port}`
  }

  return ""
}

export let API_URL = getApiUrl()

export const refreshApiUrl = () => {
  API_URL = getApiUrl()
}

// Backend app key (must match backend SPOTTERFY_API_KEY). Sent on every
// backend call; exempt endpoints (health, stream, ...) simply ignore it.
const API_KEY = process.env.NEXT_PUBLIC_SPOTTERFY_API_KEY ?? ""

export const apiHeaders = (json = true): HeadersInit => ({
  ...(json ? { "Content-Type": "application/json" } : {}),
  ...(API_KEY ? { "X-Spotterfy-Key": API_KEY } : {}),
})

/** fetch() wrapper that always attaches the backend app key. */
export const apiFetch = (url: string, init?: RequestInit): Promise<Response> => {
  const headers = new Headers(init?.headers)
  if (API_KEY && !headers.has("X-Spotterfy-Key")) {
    headers.set("X-Spotterfy-Key", API_KEY)
  }
  return fetch(url, { ...init, headers })
}
