import SpotifyDownloaderApp from "@/components/app"

export default async function JobPage({ params }: { params: Promise<{ jobId: string }> }) {
  const { jobId } = await params
  return (
    <main>
      <SpotifyDownloaderApp initialJobId={jobId} />
    </main>
  )
}
