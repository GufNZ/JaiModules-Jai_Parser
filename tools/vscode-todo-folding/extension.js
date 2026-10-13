const vscode = require("vscode");
const path = require("path");

const HEADING = /^(#{1,6})\s/;
const LIST_ITEM = /^([ \t]*)(?:[-*+]|\d+[.)])\s/;
const OPEN_TASK = /^[ \t]*(?:[-*+]|\d+[.)])\s+\[ \]/;
const FENCE = /^[ \t]*(```|~~~)/;

function indentWidth(whitespace) {
	let width = 0;
	for (const c of whitespace) {
		width = c === "\t"
			? width + 4 - width % 4
			: width + 1;
	}

	return width;
}

// Lines of every heading and list item that encloses an open task (unfolding these exposes each task), and every open task with no child items.
function openTaskLines(document) {
	const result = new Set();
	const headings = [];
	const items = [];
	let inFence = false;
	let candidate = null;
	const leaves = [];
	const settleCandidate = () => {
		if (candidate) {
			leaves.push(candidate.line);
		}

		candidate = null;
	};

	for (let line = 0; line < document.lineCount; line++) {
		const text = document.lineAt(line).text;
		if (FENCE.test(text)) {
			inFence = !inFence;
			continue;
		}


		if (inFence || text.trim() === "") {
			continue;
		}


		const heading = HEADING.exec(text);
		if (heading) {
			const level = heading[1].length;
			while (headings.length && headings[headings.length - 1].level >= level) {
				headings.pop();
			}

			headings.push({ level, line });
			items.length = 0;
			settleCandidate();
			continue;
		}


		const item = LIST_ITEM.exec(text);
		if (!item) {
			// An unindented paragraph ends any open list.
			if (!/^[ \t]/.test(text)) {
				items.length = 0;
				settleCandidate();
			}

			continue;
		}


		const indent = indentWidth(item[1]);
		while (items.length && items[items.length - 1].indent >= indent) {
			items.pop();
		}

		if (candidate) {
			if (indent > candidate.indent) {
				candidate = null;
			} else {
				settleCandidate();
			}
		}

		if (OPEN_TASK.test(text)) {
			candidate = { indent, line };

			for (const h of headings) {
				result.add(h.line);
			}
			for (const i of items) {
				result.add(i.line);
			}
		}

		items.push({ indent, line });
	}

	settleCandidate();
	return { ancestors: [...result].sort((a, b) => a - b), leaves };
}

function moveCursorToTask(editor, line) {
	const start = editor.document.lineAt(line).firstNonWhitespaceCharacterIndex;
	const position = new vscode.Position(line, start);
	editor.selection = new vscode.Selection(position, position);
	editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}

async function showOpenTasks() {
	const editor = vscode.window.activeTextEditor;
	if (!editor) {
		return;
	}


	const { ancestors, leaves } = openTaskLines(editor.document);
	await vscode.commands.executeCommand("editor.foldAll");
	if (ancestors.length) {
		await vscode.commands.executeCommand("editor.unfold", { levels: 1, selectionLines: ancestors });
	}

	if (leaves.length) {
		moveCursorToTask(editor, leaves[0]);
	}
}

// Wraps to the first leaf after the last one.
function nextOpenLeafTask() {
	const editor = vscode.window.activeTextEditor;
	if (!editor) {
		return;
	}


	const { leaves } = openTaskLines(editor.document);
	if (!leaves.length) {
		return;
	}


	const current = editor.selection.active.line;
	const next = leaves.find((line) => line > current);
	moveCursorToTask(editor, next === undefined ? leaves[0] : next);
}

function activate(context) {
	context.subscriptions.push(
		vscode.commands.registerCommand("todoFolding.showOpenTasks", showOpenTasks),
		vscode.commands.registerCommand("todoFolding.nextOpenLeafTask", nextOpenLeafTask),
		vscode.workspace.onDidSaveTextDocument(
			(document) => {
				const editor = vscode.window.activeTextEditor;
				if (
					editor && editor.document === document
					&& path.basename(document.fileName).toLowerCase() === "todo.md"
					&& vscode.workspace.getConfiguration("todoFolding").get("foldOnSave")
				) {
					showOpenTasks();
				}
			}
		)
	);
}

function deactivate() {}

module.exports = { activate, deactivate };
