import { invoke } from "@tauri-apps/api/core";
import { Ok, Error } from "./gleam.mjs";

export async function do_invoke(command, args) {
	try {
		const params = Object.fromEntries(args);
		const result = await invoke(command, params);
		return new Ok(result);
	} catch (err) {
		return new Error(err.toString());
	}
}
