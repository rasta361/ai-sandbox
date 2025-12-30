// OpenCode Plugin: Audio and terminal notifications

// Ring terminal bell
const bell = () => process.stdout.write("\x07")

// Set terminal title using ANSI escape sequence
const setTitle = (title) => process.stdout.write(`\x1b]0;${title}\x07`)

export const NotificationPlugin = async ({ project, client, $, directory, worktree }) => {
  return {
    event: async ({ event }) => {
      // Notify on session completion with session title
      if (event.type === "session.idle") {
        let text = "AI done"
        let title = null
        try {
          const sessionId = event.properties?.sessionID
          if (sessionId && client) {
            const session = await client.session.get({ path: { id: sessionId } })
            if (session.data?.title) {
              title = session.data.title
              text = `Done: ${title}`
            }
          }
        } catch (e) {
          // Fallback to default message
        }
        
        // Ring bell and update terminal title
        bell()
        setTitle(title ? `✓ ${title}` : "✓ OpenCode - Done")
        
        await $`edge-tts -t ${text} --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
      
      // Notify when permission is needed (waiting for input)
      if (event.type === "permission.updated") {
        bell()
        setTitle("⚠ OpenCode - Input needed")
        await $`edge-tts -t 'Input needed' --write-media - | ffmpeg -loglevel quiet -i - -f s16le -ar 24000 -ac 1 - | paplay --raw --rate 24000 --channels 1`
      }
    },
  }
}
