import { type Socket } from "phoenix";
import View from "./view";
import { EncodedJS, LiveSocketJSCommands } from "./js_commands";
import { HooksOptions } from "./view_hook";
/**
 * Returns true if the given element was touched by a user.
 * @param {HTMLElement} el - The element to check.
 * @returns {boolean} True if the element was touched by a user, false otherwise.
 */
export declare const isUsedInput: (el: any) => any;
/**
 * Options for configuring the LiveSocket instance.
 */
export interface LiveSocketOptions {
    /**
     * Defaults for phx-debounce and phx-throttle.
     */
    defaults?: {
        /** The millisecond phx-debounce time. Defaults to `300`. */
        debounce?: number;
        /** The millisecond phx-throttle time. Defaults to `300`. */
        throttle?: number;
    };
    /**
     * An object or function for passing connect params.
     * The function receives the element associated with a given LiveView. For example:
     *
     *     (el) => {view: el.getAttribute("data-my-view-name", token: window.myToken}
     *
     */
    params?: ((el: HTMLElement) => {
        [key: string]: any;
    }) | {
        [key: string]: any;
    };
    /**
     * The optional prefix to use for all phx DOM annotations.
     *
     * Defaults to `"phx-"`.
     */
    bindingPrefix?: string;
    /**
     * Callbacks for LiveView hooks.
     *
     * See [Client hooks via `phx-hook`](https://phoenix-live-view.hexdocs.pm/js-interop.html#client-hooks-via-phx-hook) for more information.
     */
    hooks?: HooksOptions;
    /** Callbacks for LiveView uploaders. */
    uploaders?: {
        [key: string]: any;
    };
    /** Delay in milliseconds before applying loading states. */
    loaderTimeout?: number;
    /** Delay in milliseconds before executing phx-disconnected commands. */
    disconnectedTimeout?: number;
    /** Maximum reloads before entering failsafe mode. */
    maxReloads?: number;
    /** Minimum time between normal reload attempts. */
    reloadJitterMin?: number;
    /** Maximum time between normal reload attempts. */
    reloadJitterMax?: number;
    /** Time between reload attempts in failsafe mode. */
    failsafeJitter?: number;
    /**
     * Function to log debug information. For example:
     *
     *     (view, kind, msg, obj) => console.log(`${view.id} ${kind}: ${msg} - `, obj)
     */
    viewLogger?: (view: View, kind: string, msg: string, obj: any) => void;
    /**
     * Object mapping event names to functions for populating event metadata.
     *
     *     metadata: {
     *       click: (e, el) => {
     *         return {
     *           ctrlKey: e.ctrlKey,
     *           metaKey: e.metaKey,
     *           detail: e.detail || 1,
     *         }
     *       },
     *       keydown: (e, el) => {
     *         return {
     *           key: e.key,
     *           ctrlKey: e.ctrlKey,
     *           metaKey: e.metaKey,
     *           shiftKey: e.shiftKey
     *         }
     *       }
     *     }
     *
     */
    metadata?: {
        [K in keyof HTMLElementEventMap]?: (e: HTMLElementEventMap[K], el: HTMLElement) => object;
    };
    /**
     * An optional Storage-compatible object.
     * Useful when LiveView won't have access to `sessionStorage`. For example, this could
     * happen if a site loads a cross-domain LiveView in an iframe.
     *
     * Example usage:
     *
     *     class InMemoryStorage {
     *       constructor() { this.storage = {} }
     *       getItem(keyName) { return this.storage[keyName] || null }
     *       removeItem(keyName) { delete this.storage[keyName] }
     *       setItem(keyName, keyValue) { this.storage[keyName] = keyValue }
     *     }
     */
    sessionStorage?: Storage;
    /**
     * An optional Storage-compatible object.
     * Useful when LiveView won't have access to `localStorage`.
     *
     * See {@link sessionStorage} for an example.
     */
    localStorage?: Storage;
    /**
     * If set to `true`, `phx-change` events will be blocked (will not fire)
     * while the user is composing input using an IME (Input Method Editor).
     * This is determined by the `e.isComposing` property on keyboard events,
     * which is `true` when the user is in the process of entering composed characters (for example,
     * when typing Japanese or Chinese using romaji or pinyin input methods).
     * By default, `phx-change` will not be blocked during a composition session,
     * but note that there were issues reported in older versions of Safari,
     * where a LiveView patch to the input caused unexpected behavior.
     *
     * For more information, see
     * - https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/isComposing
     * - https://github.com/phoenixframework/phoenix_live_view/issues/3322
     *
     * Defaults to `false`.
     */
    blockPhxChangeWhileComposing?: boolean;
    /** DOM callbacks. */
    dom?: {
        /**
         * An optional function to modify the behavior of querying elements in JS commands.
         * @param sourceEl - The source element, e.g. the button that was clicked.
         * @param query - The query value.
         * @param defaultQuery - A default query function that can be used if no custom query should be applied.
         * @returns A list of DOM elements.
         */
        jsQuerySelectorAll?: (sourceEl: HTMLElement, query: string, defaultQuery: () => Element[]) => Element[];
        /**
         * When defined, called with a start callback that needs to be called
         * to perform the actual patch. Failing to call the start callback causes
         * the page to become stuck.
         *
         * This can be used to delay patches in order to perform view transitions,
         * for example:
         *
         * ```javascript
         * let liveSocket = new LiveSocket("/live", Socket, {
         *   dom: {
         *     onDocumentPatch(start) {
         *       document.startViewTransition(start);
         *     }
         *   }
         * })
         * ```
         *
         * It is strongly advised to call start as quickly as possible.
         */
        onDocumentPatch?: (start: () => void) => void;
        /**
         * Called immediately before a DOM patch is applied.
         */
        onPatchStart?: (container: HTMLElement) => void;
        /**
         * Called immediately after a DOM patch is applied.
         */
        onPatchEnd?: (container: HTMLElement) => void;
        /**
         * Called when a new DOM node is added.
         */
        onNodeAdded?: (node: Node) => void;
        /**
         * Called before an element is updated.
         */
        onBeforeElUpdated?: (fromEl: Element, toEl: Element) => void;
    };
    /** Allow passthrough of other options to the Phoenix Socket constructor. */
    [key: string]: any;
}
export default class LiveSocket {
    socket: Socket;
    private bindingPrefix;
    private viewLogger;
    private metadataCallbacks;
    private defaults;
    private prevActive;
    private silenced;
    private outgoingMainEl;
    private clickStartedAtTarget;
    private linkRef;
    private roots;
    private href;
    private pendingLink;
    private currentLocation;
    private hooks;
    private reloadWithJitterTimer;
    private maxReloads;
    private reloadJitterMin;
    private reloadJitterMax;
    private failsafeJitter;
    private sessionStorage;
    private boundTopLevelEvents;
    private boundEventNames;
    private blockPhxChangeWhileComposing;
    private serverCloseRef;
    private transitions;
    /**
     * Creates a new LiveSocket instance.
     */
    constructor(
    /**
     * The WebSocket endpoint URL, e.g., `"wss://example.com/live"`, or `"/live"` to inherit the host and protocol.
     */
    url: string, 
    /**
     * The required Phoenix Socket class imported from "phoenix". For example:
     *
     * ```javascript
     * import {Socket} from "phoenix"
     * import {LiveSocket} from "phoenix_live_view"
     * let liveSocket = new LiveSocket("/live", Socket, {...})
     * ```
     */
    phxSocket: typeof Socket, 
    /**
     * Optional configuration.
     */
    opts?: Partial<LiveSocketOptions>);
    /**
     * Returns the version of the LiveView client.
     */
    version(): string;
    /**
     * Returns true if profiling is enabled. See {@link enableProfiling} and {@link disableProfiling}.
     */
    isProfileEnabled(): boolean;
    /**
     * Returns true if debugging is enabled. See {@link enableDebug} and {@link disableDebug}.
     */
    isDebugEnabled(): boolean;
    /**
     * Returns true if debugging is disabled. See {@link enableDebug} and {@link disableDebug}.
     */
    isDebugDisabled(): boolean;
    /**
     * Enables debugging.
     *
     * When debugging is enabled, the LiveView client will log debug information to the console.
     * See [Debugging client events](https://phoenix-live-view.hexdocs.pm/js-interop.html#debugging-client-events) for more information.
     */
    enableDebug(): void;
    /**
     * Enables profiling.
     *
     * When profiling is enabled, the LiveView client will log profiling information to the console.
     */
    enableProfiling(): void;
    /**
     * Disables debugging.
     */
    disableDebug(): void;
    /**
     * Disables profiling.
     */
    disableProfiling(): void;
    /**
     * Enables latency simulation.
     *
     * When latency simulation is enabled, the LiveView client will add a delay to requests and responses from the server.
     * See [Simulating Latency](https://phoenix-live-view.hexdocs.pm/js-interop.html#simulating-latency) for more information.
     */
    enableLatencySim(upperBoundMs: number): void;
    /**
     * Disables latency simulation.
     */
    disableLatencySim(): void;
    /**
     * Returns the current latency simulation upper bound.
     */
    getLatencySim(): number | null;
    /**
     * Returns the Phoenix Socket instance.
     */
    getSocket(): Socket;
    /**
     * Connects to the LiveView server.
     */
    connect(): void;
    /**
     * Disconnects from the LiveView server.
     */
    disconnect(callback?: () => void): void;
    /**
     * Can be used to replace the transport used by the underlying Phoenix Socket.
     */
    replaceTransport(transport: any): void;
    /**
     * Executes an encoded JS command, targeting the given element.
     *
     * See [`Phoenix.LiveView.JS`](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.JS.html) for more information.
     */
    execJS(el: Element, encodedJS: EncodedJS, eventType?: string | null): void;
    /**
     * Returns an object with methods to manipulate the DOM and execute JavaScript.
     * The applied changes integrate with server DOM patching.
     *
     * See [JavaScript interoperability](https://phoenix-live-view.hexdocs.pm/js-interop.html) for more information.
     */
    js(): LiveSocketJSCommands;
}
