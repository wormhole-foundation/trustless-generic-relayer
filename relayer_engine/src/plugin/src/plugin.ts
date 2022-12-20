import {
  ActionExecutor,
  assertArray,
  CommonEnv,
  CommonPluginEnv,
  ContractFilter,
  nnull,
  Plugin,
  PluginDefinition,
  Providers,
  StagingArea,
  Workflow,
} from "relayer-engine";
import * as wh from "@certusone/wormhole-sdk";
import { Logger } from "winston";
import { assertBool } from "./utils";
import {ChainId, ParsedVaaV2} from "@certusone/wormhole-sdk";
import {parseDeliveryInstructions} from "./instructions.parser";

let PLUGIN_NAME: string = "GenericRelayerPlugin";

export interface GenericRelayerPluginConfig {
  spyServiceFilters?: { chainId: wh.ChainId; emitterAddress: string }[];
  shouldRest: boolean;
  shouldSpy: boolean;
}

interface WorkflowPayload {
  vaa: string; // base64
  time: number;
  parsedInstructions: string;
}

type RelayRequest = {
  vaa: string; //The batch VAA in base64
  time: number; //Time the batch was received
  deliveryIndex: number; //The index in the delivery which has the delivery request.
  targetChain: ChainId; //The chain where the delivery will happen
  redeliver: boolean; //If the request is a redelivery or not
  maximumGas: number; //The gas limit which should be put on the transaction
  feeCoverage: BigInt; //The msg.value the relayer should put on the transaction
};

export class GenericRelayerPlugin implements Plugin<WorkflowPayload> {
  readonly shouldSpy: boolean;
  readonly shouldRest: boolean;
  static readonly pluginName: string = PLUGIN_NAME;
  readonly pluginName = GenericRelayerPlugin.pluginName;
  private static pluginConfig: GenericRelayerPluginConfig | undefined;
  pluginConfig: GenericRelayerPluginConfig;
  private smartContractAddressesByChain: {[chainId: number]: string};

  static init(pluginConfig: any): (env: CommonEnv, logger: Logger) => Plugin {
    const pluginConfigParsed: GenericRelayerPluginConfig = {
      spyServiceFilters:
        pluginConfig.spyServiceFilters && assertArray(pluginConfig.spyServiceFilters, "spyServiceFilters"),
      shouldRest: assertBool(pluginConfig.shouldRest, "shouldRest"),
      shouldSpy: assertBool(pluginConfig.shouldSpy, "shouldSpy"),
    };
    return (env, logger) => new GenericRelayerPlugin(env, pluginConfigParsed, logger);
  }

  constructor(readonly engineConfig: CommonPluginEnv, pluginConfigRaw: Record<string, any>, readonly logger: Logger) {
    console.log(`Config: ${JSON.stringify(engineConfig, undefined, 2)}`);
    console.log(`Plugin Env: ${JSON.stringify(pluginConfigRaw, undefined, 2)}`);

    this.pluginConfig = {
      spyServiceFilters:
        pluginConfigRaw.spyServiceFilters && assertArray(pluginConfigRaw.spyServiceFilters, "spyServiceFilters"),
      shouldRest: assertBool(pluginConfigRaw.shouldRest, "shouldRest"),
      shouldSpy: assertBool(pluginConfigRaw.shouldSpy, "shouldSpy"),
    };
    this.shouldRest = this.pluginConfig.shouldRest;
    this.shouldSpy = this.pluginConfig.shouldSpy;
    this.smartContractAddressesByChain = {};
    if (this.pluginConfig.spyServiceFilters?.length) {
      for (const filter of this.pluginConfig.spyServiceFilters) {
        this.smartContractAddressesByChain[filter.chainId] = filter.emitterAddress;
      }
    }
  }

  getFilters(): ContractFilter[] {
    if (this.pluginConfig.spyServiceFilters) {
      //return this.pluginConfig.spyServiceFilters;
      return []; //This plugin listens to batches, so we actually want to bypass the inbuilt filters.
    }
    this.logger.error("Contract filters not specified in config");
    throw new Error("Contract filters not specified in config");
  }

  async consumeEvent(
    vaa: Buffer,
    stagingArea: { counter?: number }
  ): Promise<{ workflowData?: WorkflowPayload; nextStagingArea?: StagingArea } | null> {
    this.logger.debug("Parsing VAA...");
    const parsed = wh.parseVaa(vaa) as ParsedVaaV2;
    //TODO figure out a way to filter for batch VAAs at the level of the spy
    // deal only with batches
    if (parsed.version != 2) {
      return null;
    }
    // only process batch if there's a vaa inside from a generic relayer smart contract.
    const emitterChain = parsed.observations[0].emitterChain;
    let addr = this.smartContractAddressesByChain[emitterChain];
    if (!addr) {
      return null;
    }

    //see if one of the observations is from a core relayer contract
    const relayerInstructions = parsed.observations.filter(obs => obs.emitterAddress.toString("hex") == addr);
    if (!relayerInstructions.length) {
      return null;
    }

    const parsedInstructions = relayerInstructions.map(instr => parseDeliveryInstructions(instr.payload));

    this.logger.debug(`Parsed VAA: ${parsed && parsed.hash}`);

    //TODO parse content from core relayer VAA
    //TODO verify that it is a transfer or resend VAA, not a redeem or something
    //TODO eject if any of these criteria aren't met

    //TODO return object with relevant relaying information in order to avoid a double-parse
    return {
      workflowData: {
        time: new Date().getTime(),
        vaa: vaa.toString("base64"),
        parsedInstructions: JSON.stringify(parsedInstructions)
      },
      nextStagingArea: {
        counter: stagingArea?.counter ? stagingArea.counter + 1 : 0,
      },
    };
  }

  async handleWorkflow(workflow: Workflow, providers: Providers, execute: ActionExecutor): Promise<void> {
    this.logger.info("Got workflow");
    this.logger.debug(JSON.stringify(workflow, undefined, 2));

    const payload = this.parseWorkflowPayload(workflow);
    const parsed = wh.parseVaa(payload.vaa);

    const pubkey = await execute.onEVM({
      chainId: 2 as ChainId,
      f: async (wallet, chainId) => {
        const pubkey = wallet.wallet.address;
        this.logger.info(`We got dat wallet pubkey ${pubkey} on chain ${chainId}`);
        this.logger.info(`Also have parsed vaa. seq: ${parsed.sequence}`);
        return pubkey;
      },
    });

    this.logger.info(`Result of action on solana ${pubkey}`);
  }

  parseWorkflowPayload(workflow: Workflow): { vaa: Buffer; time: number } {
    return {
      vaa: Buffer.from(workflow.data.vaa, "base64"),
      time: workflow.data.time as number,
    };
  }
}

class Definition implements PluginDefinition<GenericRelayerPluginConfig, Plugin> {
  pluginName: string = PLUGIN_NAME;

  defaultConfig(env: CommonPluginEnv): GenericRelayerPluginConfig {
    return 1 as any;
  }
  init(pluginConfig?: any): (engineConfig: any, logger: Logger) => Plugin {
    if (!pluginConfig) {
      return (env, logger) => {
        const defaultPluginConfig = this.defaultConfig(env);
        return new GenericRelayerPlugin(env, pluginConfigParsed, logger);
      };
    }
    const pluginConfigParsed: GenericRelayerPluginConfig = {
      spyServiceFilters:
        pluginConfig.spyServiceFilters && assertArray(pluginConfig.spyServiceFilters, "spyServiceFilters"),
      shouldRest: assertBool(pluginConfig.shouldRest, "shouldRest"),
      shouldSpy: assertBool(pluginConfig.shouldSpy, "shouldSpy"),
    };
    return (env, logger) => new GenericRelayerPlugin(env, pluginConfigParsed, logger);
  }
}

export default new Definition();
