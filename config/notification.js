// OpenCode Plugin: Audio notifications

export const NotificationPlugin = async ({ project, client, $, directory, worktree }) => {
  return {
    event: async ({ event }) => {
      // Notify on session completion with session title
      if (event.type === "session.idle") {
        let text = "AI done"
        try {
          const sessionId = event.properties?.sessionID
          if (sessionId && client) {
            const session = await client.session.get({ path: { id: sessionId } })
            if (session.data?.title) {
              text = `Done: ${session.data.title}`
            }
          }
        } catch (e) {
          // Fallback to default message
        }
        await $`edge-tts -t ${text} --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
      // Notify when permission is needed (waiting for input)
      if (event.type === "permission.updated") {
        await $`edge-tts -t 'Input needed' --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
    },
  }
}
