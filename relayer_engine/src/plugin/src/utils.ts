export class PluginError extends Error {
  constructor(msg: string, public args: Record<any, any>) {
    super(msg)
  }
}
