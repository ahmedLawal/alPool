const ROUTING_MODES = new Set([
  'balance',
  'prefer-claude',
  'prefer-zai',
  'prefer-kimi',
  'sticky',
]);

export class ControlError extends Error {
  constructor(message, status = 400, code = 'invalid_command') {
    super(message);
    this.name = 'ControlError';
    this.status = status;
    this.code = code;
  }
}

export class ControlService {
  constructor({
    accountManager,
    config,
    persistConfig,
    syncAccounts,
    checkForUpdates,
    getUpstreamSyncStatus = () => null,
    getActivity = () => ({ activeCount: 0, sessionCount: 0, active: [], recent: [] }),
    requestRestart,
    requestStop,
    log = () => {},
  }) {
    this.am = accountManager;
    this.config = config;
    this.persistConfig = persistConfig;
    this.syncAccounts = syncAccounts;
    this.checkForUpdates = checkForUpdates;
    this.getUpstreamSyncStatus = getUpstreamSyncStatus;
    this.getActivity = getActivity;
    this.requestRestart = requestRestart;
    this.requestStop = requestStop;
    this.log = log;
  }

  snapshot() {
    const status = this.am.getStatus();
    const upstreamSync = this.getUpstreamSyncStatus?.() || {
      state: 'unknown',
      phase: null,
      checkedAt: null,
      lastSuccessAt: null,
      installedVersion: status.version?.current ?? null,
      installedRevision: status.version?.currentRevision ?? null,
      availableVersion: null,
      availableRevision: null,
      error: null,
    };
    return {
      ...status,
      upstreamSync,
      activity: this.getActivity(),
      control: {
        generatedAt: new Date().toISOString(),
        backendPid: process.pid,
        automaticUpdates: this._automaticUpdatesOn(),
        capabilities: {
          setRoutingMode: true,
          preferAccount: true,
          manageAccounts: true,
          addAccounts: false,
          syncAccounts: true,
          manageUpdates: true,
          restart: true,
          stop: true,
        },
      },
    };
  }

  async execute(command) {
    if (!command || typeof command !== 'object' || Array.isArray(command)) {
      throw new ControlError('Command must be a JSON object.');
    }
    const type = String(command.type || '');
    const payload = command.payload && typeof command.payload === 'object'
      ? command.payload
      : {};

    switch (type) {
      case 'set-routing-mode':
        return this._setRoutingMode(payload.mode);
      case 'set-preferred-account':
        return this._setPreferredAccount(payload.name);
      case 'set-provider-fallback':
        return this._setProviderFallback(payload.provider, payload.policy);
      case 'set-account-enabled':
        return this._setAccountEnabled(payload.name, payload.enabled);
      case 'rename-account':
        return this._renameAccount(payload.name, payload.newName);
      case 'delete-account':
        return this._deleteAccount(payload.name);
      case 'set-automatic-updates':
        return this._setAutomaticUpdates(payload.enabled);
      case 'sync-accounts':
        return this._syncAccounts();
      case 'check-update':
        return this._checkUpdate();
      case 'restart':
        return this._deferLifecycle('Restart requested', this.requestRestart);
      case 'stop':
        return this._deferLifecycle('Graceful stop requested', this.requestStop);
      default:
        throw new ControlError(`Unknown control command: ${type || '(missing)'}`);
    }
  }

  _automaticUpdatesOn() {
    return this.config.updateCheck !== false
      && this.config.autoUpdate === true
      && this.config.autoApply === true;
  }

  _findAccount(name) {
    const index = this.am.accounts.findIndex(account => account.name === name);
    if (index < 0) throw new ControlError(`Account "${name}" was not found.`, 404, 'not_found');
    return { account: this.am.accounts[index], index };
  }

  _configLocation(account) {
    if (account.accountUuid) {
      const index = this.config.accounts.findIndex(item => item.accountUuid === account.accountUuid);
      if (index >= 0) return { array: 'accounts', index };
    }
    const accountIndex = this.config.accounts.findIndex(item => item.name === account.name);
    if (accountIndex >= 0) return { array: 'accounts', index: accountIndex };
    const providerIndex = Array.isArray(this.config.providers)
      ? this.config.providers.findIndex(item => item.name === account.name)
      : -1;
    return providerIndex >= 0 ? { array: 'providers', index: providerIndex } : null;
  }

  async _setRoutingMode(mode) {
    if (!ROUTING_MODES.has(mode)) throw new ControlError(`Invalid routing mode: ${mode}`);
    if (!this.am.setProviderRoutingMode(mode)) throw new ControlError(`Could not set routing mode: ${mode}`);
    this.config.scheduler = { ...(this.config.scheduler || {}), routingMode: mode };
    delete this.config.scheduler.crossProviderFallbackPolicy;
    await this.persistConfig();
    return this._success(`Routing mode set to ${mode}`);
  }

  async _setPreferredAccount(name) {
    if (name == null || name === '') {
      this.config.routing = { mode: 'automatic', preferredAccount: null };
      this.am.setRoutingMode('automatic');
      await this.persistConfig();
      return this._success('Automatic account selection enabled');
    }
    const { account } = this._findAccount(String(name));
    if (account.type === 'provider' || !account.enabled) {
      throw new ControlError(`Claude account "${name}" must be enabled before it can be preferred.`);
    }
    this.config.routing = { mode: 'preferred', preferredAccount: account.name };
    if (!this.am.setRoutingMode('preferred', account.name)) {
      throw new ControlError(`Could not prefer account "${name}".`);
    }
    await this.persistConfig();
    return this._success(`Routing now prefers "${account.name}" with automatic failover`);
  }

  async _setProviderFallback(provider, policy) {
    if (!['zai', 'kimi'].includes(provider)) throw new ControlError(`Invalid provider: ${provider}`);
    if (!['never', 'when-exhausted', 'always'].includes(policy)) throw new ControlError(`Invalid provider fallback policy: ${policy}`);
    if (!this.am.setClaudeFallbackForProvider?.(provider, policy)) {
      throw new ControlError(`Could not set ${provider} fallback policy.`);
    }
    this.config.scheduler = { ...(this.config.scheduler || {}) };
    this.config.scheduler.providers = { ...(this.config.scheduler.providers || {}) };
    this.config.scheduler.providers[provider] = {
      ...(this.config.scheduler.providers[provider] || {}),
      claudeFallback: policy,
    };
    await this.persistConfig();
    return this._success(`${provider === 'zai' ? 'GLM' : 'Kimi'} fallback set to ${policy}`);
  }

  async _setAccountEnabled(name, enabled) {
    if (typeof enabled !== 'boolean') throw new ControlError('enabled must be a boolean.');
    const { account, index } = this._findAccount(String(name));
    const location = this._configLocation(account);
    const previous = account.enabled;
    const previousRouting = this.config.routing;

    if (location?.array === 'accounts') {
      this.config.accounts[location.index].enabled = enabled;
    } else if (location?.array === 'providers') {
      this.config.providers[location.index].enabled = enabled;
    } else if (account.type !== 'provider') {
      throw new ControlError(`Account "${name}" is not backed by configuration.`);
    }
    if (!enabled && this.config.routing?.preferredAccount === account.name) {
      this.config.routing = { mode: 'automatic', preferredAccount: null };
    }
    this.am.setAccountEnabled(index, enabled);
    try {
      if (location) await this.persistConfig();
    } catch (error) {
      this.am.setAccountEnabled(index, previous);
      if (location) this.config[location.array][location.index].enabled = previous;
      this.config.routing = previousRouting;
      throw error;
    }
    return this._success(`${enabled ? 'Enabled' : 'Disabled'} "${account.name}"`);
  }

  async _renameAccount(name, newName) {
    const next = String(newName || '').trim();
    if (!next) throw new ControlError('New account name cannot be empty.');
    const { account } = this._findAccount(String(name));
    if (this.am.accounts.some(candidate => candidate !== account && candidate.name === next)) {
      throw new ControlError(`An account named "${next}" already exists.`, 409, 'conflict');
    }
    const location = this._configLocation(account);
    if (!location) throw new ControlError(`Account "${name}" comes from a running session and cannot be renamed.`);
    const previousName = account.name;
    this.config[location.array][location.index].name = next;
    if (this.config.routing?.preferredAccount === previousName) this.config.routing.preferredAccount = next;
    try {
      await this.persistConfig();
      account.name = next;
    } catch (error) {
      this.config[location.array][location.index].name = previousName;
      if (this.config.routing?.preferredAccount === next) this.config.routing.preferredAccount = previousName;
      throw error;
    }
    return this._success(`Renamed "${previousName}" to "${next}"`);
  }

  async _deleteAccount(name) {
    const { account, index } = this._findAccount(String(name));
    if (account.inFlight > 0) {
      throw new ControlError(`Cannot delete "${name}" while ${account.inFlight} request(s) are active.`, 409, 'account_busy');
    }
    const location = this._configLocation(account);
    if (!location) throw new ControlError(`Account "${name}" comes from a running session and cannot be deleted.`);
    const previousEnabled = account.enabled;
    const previousRouting = this.config.routing;
    this.am.setAccountEnabled(index, false);
    const [removed] = this.config[location.array].splice(location.index, 1);
    if (this.config.routing?.preferredAccount === account.name) {
      this.config.routing = { mode: 'automatic', preferredAccount: null };
    }
    try {
      await this.persistConfig();
      if (!this.am.removeAccount(index)) throw new ControlError(`Account "${name}" became active before deletion completed.`, 409, 'account_busy');
    } catch (error) {
      this.config[location.array].splice(location.index, 0, removed);
      this.config.routing = previousRouting;
      this.am.setAccountEnabled(index, previousEnabled);
      await this.persistConfig().catch(() => {});
      throw error;
    }
    return this._success(`Deleted "${name}"`);
  }

  async _setAutomaticUpdates(enabled) {
    if (typeof enabled !== 'boolean') throw new ControlError('enabled must be a boolean.');
    this.config.updateCheck = true;
    this.config.autoUpdate = enabled;
    this.config.autoApply = enabled;
    await this.persistConfig();
    return this._success(`Automatic updates ${enabled ? 'enabled' : 'disabled'}`);
  }

  async _syncAccounts() {
    if (!this.syncAccounts) throw new ControlError('Account sync is unavailable.', 503, 'unavailable');
    const added = await this.syncAccounts();
    return this._success(added > 0 ? `Loaded ${added} new account(s)` : 'Accounts and credentials refreshed');
  }

  async _checkUpdate() {
    if (!this.checkForUpdates) throw new ControlError('Update checks are unavailable.', 503, 'unavailable');
    await this.checkForUpdates();
    return this._success('Update check started');
  }

  _deferLifecycle(message, callback) {
    if (!callback) throw new ControlError(`${message} is unavailable.`, 503, 'unavailable');
    const timer = setTimeout(() => callback(), 100);
    timer.unref?.();
    return this._success(message);
  }

  _success(message) {
    this.log(message);
    return { ok: true, message };
  }
}
