import { cert, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

export interface PushMessage { title: string; body: string; threadId: string; taskId: string }

export interface PushProvider {
  readonly name: string;
  /** Returns the tokens the push service says are no longer valid, so they can be deleted. */
  send(tokens: string[], msg: PushMessage): Promise<{ invalidTokens: string[] }>;
}

const DEAD = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token', 'messaging/invalid-argument']);

/** Firebase Cloud Messaging. One notification per thread on the phone (collapse key / tag = thread id). */
export class FcmPush implements PushProvider {
  readonly name = 'fcm';
  private app: App;
  constructor(serviceAccountBase64: string) {
    this.app = initializeApp({ credential: cert(JSON.parse(Buffer.from(serviceAccountBase64, 'base64').toString('utf8'))) }, 'taskplus');
  }

  async send(tokens: string[], m: PushMessage) {
    if (!tokens.length) return { invalidTokens: [] };
    const r = await getMessaging(this.app).sendEachForMulticast({
      tokens,
      notification: { title: m.title, body: m.body },
      data: { threadId: m.threadId, taskId: m.taskId },
      android: { collapseKey: m.threadId, notification: { tag: m.threadId, channelId: 'tasks' } },
      apns: { headers: { 'apns-collapse-id': m.threadId }, payload: { aps: { threadId: m.threadId } } },
    });
    return { invalidTokens: r.responses.flatMap((x, i) => (!x.success && DEAD.has(x.error?.code ?? '') ? [tokens[i]!] : [])) };
  }
}

/** Records pushes instead of sending them: tests, and running before Firebase is set up. */
export class MemoryPush implements PushProvider {
  readonly name = 'memory';
  readonly sent: { tokens: string[]; msg: PushMessage }[] = [];
  invalid = new Set<string>();
  async send(tokens: string[], msg: PushMessage) {
    this.sent.push({ tokens, msg });
    return { invalidTokens: tokens.filter((t) => this.invalid.has(t)) };
  }
}
