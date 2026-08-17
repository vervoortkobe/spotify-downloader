export const getApiUrl = () => {
  if (process.env.NEXT_PUBLIC_API_URL) {
    const url = process.env.NEXT_PUBLIC_API_URL.replace(/\/+$/, "").replace(/\/api$/, "")
    return url.match(/^https?:\/\/|^\/\//) ? url : `https://${url}`
  }

  if (typeof window !== "undefined") {
    const { protocol, hostname } = window.location
    const port = hostname === "localhost" || hostname === "127.0.0.1" ? ":5000" : ""
    return `${protocol}//${hostname}${port}`
  }

  return ""
}

export let API_URL = getApiUrl()

export const refreshApiUrl = () => {
  API_URL = getApiUrl()
}
