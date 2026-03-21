"use client"

import { useState, useEffect } from "react"
import {
  Music2,
  Download,
  Loader2,
  Sparkles,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Progress } from "@/components/ui/progress"
import { ScrollArea } from "@/components/ui/scroll-area"
import { toast, Toaster } from "react-hot-toast"
import Image from "next/image"

interface Track {
  id: string
  title: string
  artists: string
  album: string
  cover: string
  releaseDate: string
  downloadLink: string
}

export default function SunnifyApp() {
  const [playlistLink, setPlaylistLink] = useState("")

  useEffect(() => {
    setPlaylistLink("")
  }, [])
  const [downloadProgress, setDownloadProgress] = useState(0)
  const [songsDownloaded, setSongsDownloaded] = useState(0)
  const [totalSongs, setTotalSongs] = useState(0)
  const [playlistName, setPlaylistName] = useState("")
  const [isProcessing, setIsProcessing] = useState(false)
  const [statusMessage, setStatusMessage] = useState("Paste a Spotify URL to begin")
  const [tracks, setTracks] = useState<Track[]>([])
  const [selectedTrack, setSelectedTrack] = useState<Track | null>(null)
  const [showBanner, setShowBanner] = useState(true)
  const [isDownloadingTrack, setIsDownloadingTrack] = useState<string | null>(null)
  const [isDownloadingAll, setIsDownloadingAll] = useState(false)
  const [trackProgress, setTrackProgress] = useState<Record<string, number>>({})
  const NEXT_PUBLIC_API_URL = process.env.NEXT_PUBLIC_API_URL || "http://127.0.0.1:5000"
  // Sanitize the URL: remove trailing slash and trailing '/api' if included by mistake
  const LOCAL_API = NEXT_PUBLIC_API_URL.replace(/\/+$/, "").replace(/\/api$/, "")

  const downloadTrack = async (track: Track) => {
    try {
      setIsDownloadingTrack(track.id)
      setTrackProgress((prev) => ({ ...prev, [track.id]: 0 }))

      const interval = setInterval(async () => {
        try {
          const res = await fetch(`${LOCAL_API}/api/progress/${track.id}`)
          if (res.ok) {
            const data = await res.json()
            setTrackProgress((prev) => ({ ...prev, [track.id]: data.progress || 0 }))
          }
        } catch (e) { }
      }, 500)

      const res = await fetch(`${LOCAL_API}/api/download-track`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(track),
      })

      clearInterval(interval)
      setTrackProgress((prev) => ({ ...prev, [track.id]: 100 }))

      if (!res.ok) throw new Error("Failed to download track")

      const blob = await res.blob()
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${track.title} - ${track.artists}.mp3`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)
      toast.success(`Downloaded ${track.title}`)

      setTimeout(() => {
        setTrackProgress((prev) => {
          const newState = { ...prev }
          delete newState[track.id]
          return newState
        })
      }, 1500)
    } catch (err) {
      console.error(err)
      toast.error("Download failed")
      setTrackProgress((prev) => {
        const newState = { ...prev }
        delete newState[track.id]
        return newState
      })
    } finally {
      setIsDownloadingTrack(null)
    }
  }

  const downloadAll = async () => {
    if (tracks.length === 0) return
    try {
      setIsDownloadingAll(true)
      toast.loading("Zipping playlist, this might take a while...", { id: "zip-toast" })

      const interval = setInterval(async () => {
        try {
          const res = await fetch(`${LOCAL_API}/api/progress/all`)
          if (res.ok) {
            const data = await res.json()
            setTrackProgress((prev) => {
              const ns = { ...prev }
              tracks.forEach(t => {
                if (data[t.id] !== undefined) {
                  ns[t.id] = data[t.id]
                }
              })
              return ns
            })
          }
        } catch (e) { }
      }, 500)

      const res = await fetch(`${LOCAL_API}/api/download-playlist-zip`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tracks, playlistName }),
      })

      clearInterval(interval)

      if (!res.ok) throw new Error("Failed to zip playlist")

      const blob = await res.blob()
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${playlistName || "Playlist"}.zip`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      window.URL.revokeObjectURL(url)

      toast.success("Playlist downloaded", { id: "zip-toast" })

      setTimeout(() => {
        setTrackProgress({})
      }, 1500)
    } catch (err) {
      console.error(err)
      toast.error("Zip download failed", { id: "zip-toast" })
      setTrackProgress({})
    } finally {
      setIsDownloadingAll(false)
    }
  }

  const handleProcess = async () => {
    if (!playlistLink) {
      toast.error("Please enter a Spotify URL")
      return
    }

    if (!playlistLink.includes("open.spotify.com")) {
      toast.error("Invalid URL - must be from open.spotify.com")
      return
    }

    setIsProcessing(true)
    setDownloadProgress(0)
    setSongsDownloaded(0)
    setTotalSongs(0)
    setStatusMessage("Fetching playlist data...")
    setTracks([])
    setSelectedTrack(null)

    try {
      const response = await fetch(
        `${LOCAL_API}/api/scrape-playlist`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ playlistUrl: playlistLink }),
        }
      )

      if (!response.ok) throw new Error("Failed to process playlist")

      const result = await response.json()

      if (result.event === "complete") {
        setPlaylistName(result.data.playlistName || "Playlist")
        const processedTracks: Track[] = result.data.tracks || []
        setTracks(processedTracks)
        setTotalSongs(processedTracks.length)
        setSongsDownloaded(processedTracks.length)
        setDownloadProgress(100)
        setStatusMessage(`Found ${processedTracks.length} tracks`)

        if (processedTracks.length > 0) {
          setSelectedTrack(processedTracks[0])
        }

        toast.success(`Loaded ${processedTracks.length} tracks!`)
        setPlaylistLink("")
      } else if (result.event === "error") {
        throw new Error(result.data?.message || "Processing failed")
      }
    } catch (error) {
      console.error("Error:", error)
      toast.error(error instanceof Error ? error.message : "Failed to process")
      setStatusMessage("Error - try again")
    } finally {
      setIsProcessing(false)
    }
  }

  return (
    <div className="relative min-h-screen overflow-hidden bg-black text-white">
      {/* Animated background */}
      <div className="pointer-events-none absolute inset-0">
        <div className="absolute -left-1/4 -top-1/4 h-[800px] w-[800px] rounded-full bg-green-500/10 blur-[120px]" />
        <div className="absolute -bottom-1/4 -right-1/4 h-[600px] w-[600px] rounded-full bg-emerald-500/10 blur-[100px]" />
        <div className="absolute left-1/2 top-1/2 h-[400px] w-[400px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-green-600/5 blur-[80px]" />
      </div>

      <Toaster
        position="top-center"
        toastOptions={{
          style: { background: "#1a1a1a", color: "#fff", border: "1px solid #333" },
        }}
      />

      <div className="relative mx-auto flex min-h-screen max-w-7xl flex-col px-4 py-8 sm:px-6 lg:px-8">
        {/* Main Content */}
        <div className="grid flex-1 gap-8 lg:grid-cols-[1fr,380px]">
          {/* Left Column */}
          <div className="space-y-6">
            {/* Search Card */}
            <div className="group relative overflow-hidden rounded-3xl border border-white/10 bg-white/5 p-8 backdrop-blur-xl transition-all hover:border-green-500/30 hover:bg-white/[0.07]">
              <div className="absolute -right-20 -top-20 h-40 w-40 rounded-full bg-green-500/10 blur-3xl transition-all group-hover:bg-green-500/20" />

              <div className="relative">
                <div className="mb-6 flex items-center gap-3">
                  <Sparkles className="h-5 w-5 text-green-400" />
                  <h2 className="text-xl font-bold">Enter Spotify URL</h2>
                </div>

                <div className="flex gap-4">
                  <div className="relative flex-1">
                    <Input
                      type="text"
                      placeholder="https://open.spotify.com/playlist/..."
                      value={playlistLink}
                      onChange={(e) => setPlaylistLink(e.target.value)}
                      onKeyDown={(e) => e.key === "Enter" && !isProcessing && handleProcess()}
                      className="h-14 rounded-xl border-white/10 bg-black/50 pl-5 pr-5 text-base text-white placeholder:text-gray-500 focus:border-green-500 focus:ring-2 focus:ring-green-500/20"
                    />
                  </div>
                  <Button
                    onClick={handleProcess}
                    disabled={isProcessing}
                    className="h-14 rounded-xl bg-gradient-to-r from-green-500 to-emerald-500 px-8 text-base font-bold text-black shadow-lg shadow-green-500/25 transition-all hover:scale-105 hover:shadow-green-500/40 disabled:scale-100 disabled:opacity-50"
                  >
                    {isProcessing ? (
                      <Loader2 className="h-6 w-6 animate-spin" />
                    ) : (
                      <>
                        <Download className="mr-2 h-5 w-5" />
                        Fetch
                      </>
                    )}
                  </Button>
                </div>

                {/* Progress */}
                <div className="mt-6 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-400">{statusMessage}</span>
                    {totalSongs > 0 && (
                      <span className="rounded-full bg-green-500/10 px-3 py-1 text-sm font-semibold text-green-400">
                        {songsDownloaded} / {totalSongs}
                      </span>
                    )}
                  </div>
                  <Progress
                    value={downloadProgress}
                    className="h-2 rounded-full bg-white/10 [&>div]:rounded-full [&>div]:bg-gradient-to-r [&>div]:from-green-400 [&>div]:to-emerald-500"
                  />
                  {playlistName && (
                    <p className="text-sm">
                      <span className="text-gray-500">Playlist:</span>{" "}
                      <span className="font-medium text-white">{playlistName}</span>
                    </p>
                  )}
                </div>
              </div>
            </div>

            {/* Track List */}
            <div className="overflow-hidden rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl">
              <div className="border-b border-white/10 px-8 py-5 flex justify-between items-center">
                <h2 className="text-xl font-bold">
                  {tracks.length > 0 ? `${tracks.length} Tracks` : "Track List"}
                </h2>
                {tracks.length > 0 && (
                  <Button
                    onClick={downloadAll}
                    disabled={isDownloadingAll}
                    className="h-10 rounded-xl bg-gradient-to-r from-green-500 to-emerald-500 px-4 text-sm font-bold text-black shadow-lg shadow-green-500/25 transition-all hover:scale-105 hover:shadow-green-500/40 disabled:scale-100 disabled:opacity-50"
                  >
                    {isDownloadingAll ? (
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    ) : (
                      <Download className="mr-2 h-4 w-4" />
                    )}
                    {isDownloadingAll ? "Zipping..." : "Download All (ZIP)"}
                  </Button>
                )}
              </div>

              {tracks.length === 0 ? (
                <div className="flex h-80 flex-col items-center justify-center px-8 text-center">
                  <div className="mb-4 rounded-full bg-white/5 p-6">
                    <Music2 className="h-10 w-10 text-gray-600" />
                  </div>
                  <p className="text-lg font-medium text-gray-400">No tracks yet</p>
                  <p className="mt-1 text-sm text-gray-600">
                    Enter a Spotify playlist or track URL above
                  </p>
                </div>
              ) : (
                <ScrollArea className="h-[420px]">
                  <div className="divide-y divide-white/5">
                    {tracks.map((track, index) => (
                      <div key={track.id || index} className="relative flex flex-col">
                        <div
                          onClick={() => setSelectedTrack(track)}
                          className={`flex cursor-pointer items-center gap-4 px-6 py-4 transition-all hover:bg-white/5 ${selectedTrack?.id === track.id ? "bg-green-500/10" : ""
                            }`}
                        >
                          <span className="w-8 text-center text-sm font-medium text-gray-500">
                            {index + 1}
                          </span>
                          {track.cover ? (
                            <Image
                              src={track.cover}
                              alt=""
                              width={56}
                              height={56}
                              className="h-14 w-14 rounded-lg object-cover shadow-lg"
                              unoptimized
                            />
                          ) : (
                            <div className="flex h-14 w-14 items-center justify-center rounded-lg bg-white/10">
                              <Music2 className="h-6 w-6 text-gray-500" />
                            </div>
                          )}
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-semibold">{track.title}</p>
                            <p className="truncate text-sm text-gray-400">{track.artists}</p>
                          </div>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={(e) => {
                              e.stopPropagation()
                              downloadTrack(track)
                            }}
                            disabled={isDownloadingTrack === track.id}
                            className="text-green-400 hover:bg-green-500/20 hover:text-green-300 pointer-events-auto shrink-0 z-10"
                          >
                            {isDownloadingTrack === track.id ? (
                              <Loader2 className="h-5 w-5 animate-spin" />
                            ) : (
                              <Download className="h-5 w-5" />
                            )}
                          </Button>
                        </div>
                        {trackProgress[track.id] !== undefined && (
                          <div className="absolute bottom-0 left-0 right-0 px-6 pb-1.5 pointer-events-none flex items-center gap-2">
                            <Progress
                              value={trackProgress[track.id]}
                              className="h-1 flex-1 rounded-full bg-white/10 [&>div]:rounded-full [&>div]:bg-gradient-to-r [&>div]:from-green-400 [&>div]:to-emerald-500"
                            />
                            <span className="w-8 text-right text-[10px] font-bold text-green-400">
                              {Math.round(trackProgress[track.id])}%
                            </span>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </ScrollArea>
              )}
            </div>
          </div>

          {/* Right Column */}
          <div className="space-y-6">
            {/* Now Playing */}
            <div className="overflow-hidden rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl">
              <div className="border-b border-white/10 px-6 py-4">
                <h2 className="font-bold">Track Details</h2>
              </div>

              <div className="p-6">
                {selectedTrack ? (
                  <div className="space-y-6">
                    <div className="relative mx-auto aspect-square w-full max-w-[280px] overflow-hidden rounded-2xl shadow-2xl shadow-black/50">
                      {selectedTrack.cover ? (
                        <Image
                          src={selectedTrack.cover}
                          alt={selectedTrack.title}
                          fill
                          className="object-cover"
                          unoptimized
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-gray-800 to-gray-900">
                          <Music2 className="h-20 w-20 text-gray-700" />
                        </div>
                      )}
                      <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
                    </div>

                    <div className="space-y-4">
                      <div>
                        <p className="mb-1 text-xs font-semibold uppercase tracking-widest text-green-400">
                          Title
                        </p>
                        <p className="text-lg font-bold leading-tight">{selectedTrack.title}</p>
                      </div>
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <p className="mb-1 text-xs font-semibold uppercase tracking-widest text-gray-500">
                            Artist
                          </p>
                          <p className="text-sm text-gray-300">{selectedTrack.artists}</p>
                        </div>
                        <div>
                          <p className="mb-1 text-xs font-semibold uppercase tracking-widest text-gray-500">
                            Album
                          </p>
                          <p className="text-sm text-gray-300">{selectedTrack.album || "—"}</p>
                        </div>
                        <div className="col-span-2">
                          <p className="mb-1 text-xs font-semibold uppercase tracking-widest text-gray-500">
                            Release Date
                          </p>
                          <p className="text-sm text-gray-300">
                            {selectedTrack.releaseDate || "—"}
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="flex aspect-square flex-col items-center justify-center rounded-2xl bg-black/30 text-center">
                    <Music2 className="mb-3 h-16 w-16 text-gray-700" />
                    <p className="font-medium text-gray-500">Select a track</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
