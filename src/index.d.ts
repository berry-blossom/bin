/* eslint-disable @typescript-eslint/no-explicit-any */
interface Connection {
	Disconnect(...args: unknown[]): void;
}

declare namespace Bin {
	export interface Destroyable {
		Destroy(): void;
	}
	export type Task = (() => void) | thread | RBXScriptConnection | Connection | Bin.Destroyable;
}

/**
 * Easy cleanup utility.
 *
 * Runs functions, destroys instances/tables, disconnects events, and stops threads.
 *
 *
 *	```ts
 *	const bin = new Bin();
 *
 *	bin.Add(() => print("Hello World!"));
 *
 *	bin.Destroy();
 * ```
 */
type Bin = {
	[index in number | string]: Bin.Task | undefined;
} & {
	/**
	 * Add a task to the bin, returns the index of the task.
	 * The task can be gotten with Bin:Get, and cleaned with Bin:CleanPosition.
	 * */
	Add<T extends Bin.Task | undefined>(tsk: T): number;
	/**
	 * Adds a Promise to the Bin as a task. This is done by doing the following
	 *
	 *	- Check if the Promise is started.
	 *		- If not, it is assumed the Promise has resolved and is not added as a task.
	 *	- Add the Promise to the bin as a task with a unique id.
	 *	- Add `finally` to the Promise chain to cancel the Promise after it resolves.
	 *
	 *	The Promise is then returned.
	 */
	AddPromise<P>(promise: Promise<P>): Promise<P>;
	/** Gets a task in the Bin based on the index return from Bin:Add */
	Get(idx: number): Bin.Task;
	/**
	 * Cleans an index in the bin.
	 * This method will not move any of the slots in the Bin.
	 */
	ClearPosition(idx: number): void;
	/**
	 * Cleans all tasks in the bin.
	 *
	 * Any values stored within the bin will be cleaned up as following:
	 *	- Functions are ran.
	 *		- Be sure any functions will not yield, as this will cause this method to yield as well.
	 *		- The function is called with pcall, so no errors will occur
	 *	- Instances are destroyed with :Destroy().
	 *	- RBXScriptConnections will first check if they are connected. If they are, they will disconnect.
	 *	- Threads will be canceled with task.cancel.
	 *		- The cancellation is wrapped in a pcall, so no errors will occur
	 *	- Tables with a "Destroy" method will call that method.
	 *		- This is wrapped in a pcall, and the first argument should always be self!
	 *		- Tables without a "Destroy" method will throw a warning to the console, but will be dereferenced.
	 *	- All other values will be dereferenced with `table.clear`.
	 */
	Clean(): void;
	/**
	 * Freezes the bin, not allowing for any more tasks to be added.
	 * Tasks are still allowed to be cleaned up while frozen.
	 */
	Freeze(): void;
	/** Unfreezes the bin, allowing for new tasks to be added. */
	Unfreeze(): void;
	/** Gets whether or not the bin is frozen. */
	IsFrozen(): boolean;
	/** Destroy the bin entirely, meaning it will be ready to be GC'd. */
	Destroy(): void;
};

interface Constructor {
	/**
	 * Creates a new bin.
	 */
	new (): Bin;
}

declare const Bin: Constructor;

export = Bin;
