// Entry for restoria-idlerpg-staging. workerd rejects an entry module with
// named exports that are not handlers, so the gate logic lives beside it.
import { handleStagingGate, type StagingGateEnv } from './staging_gate'

export default {
  fetch(request: Request, env: StagingGateEnv): Promise<Response> {
    return handleStagingGate(request, env)
  },
}
