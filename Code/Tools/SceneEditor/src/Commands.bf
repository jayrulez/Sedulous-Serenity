namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.Framework.Scenes;

// ==================== Command Interface ====================

/// Interface for undoable editor commands.
interface IEditorCommand
{
	/// Executes (or re-executes) the command.
	void Execute();

	/// Reverses the command.
	void Undo();

	/// Gets a human-readable description for UI display.
	void GetDescription(String outStr);
}

// ==================== Command History ====================

/// Manages undo/redo stacks for a single scene tab.
class CommandHistory
{
	private List<IEditorCommand> mUndoStack = new .() ~ DeleteContainerAndItems!(_);
	private List<IEditorCommand> mRedoStack = new .() ~ DeleteContainerAndItems!(_);

	public bool CanUndo => mUndoStack.Count > 0;
	public bool CanRedo => mRedoStack.Count > 0;

	/// Executes a command and pushes it onto the undo stack.
	/// Clears the redo stack (new action invalidates redo history).
	public void Execute(IEditorCommand cmd)
	{
		cmd.Execute();
		mUndoStack.Add(cmd);
		ClearRedoStack();
	}

	/// Pushes an already-executed command onto the undo stack.
	/// Use when the action was performed externally (e.g., gizmo drag).
	public void Push(IEditorCommand cmd)
	{
		mUndoStack.Add(cmd);
		ClearRedoStack();
	}

	/// Undoes the most recent command.
	public void Undo()
	{
		if (mUndoStack.Count == 0) return;
		let cmd = mUndoStack.PopBack();
		cmd.Undo();
		mRedoStack.Add(cmd);
	}

	/// Redoes the most recently undone command.
	public void Redo()
	{
		if (mRedoStack.Count == 0) return;
		let cmd = mRedoStack.PopBack();
		cmd.Execute();
		mUndoStack.Add(cmd);
	}

	/// Clears all history.
	public void Clear()
	{
		DeleteContainerAndItems!(mUndoStack);
		mUndoStack = new .();
		ClearRedoStack();
	}

	private void ClearRedoStack()
	{
		DeleteContainerAndItems!(mRedoStack);
		mRedoStack = new .();
	}
}

// ==================== Transform Command ====================

/// Sets an entity's transform. Captures old and new values for undo/redo.
class SetTransformCommand : IEditorCommand
{
	private Scene mScene;
	private EntityId mEntity;
	private Transform mOldTransform;
	private Transform mNewTransform;

	public this(Scene scene, EntityId entity, Transform oldTransform, Transform newTransform)
	{
		mScene = scene;
		mEntity = entity;
		mOldTransform = oldTransform;
		mNewTransform = newTransform;
	}

	public void Execute()
	{
		mScene.SetTransform(mEntity, mNewTransform);
	}

	public void Undo()
	{
		mScene.SetTransform(mEntity, mOldTransform);
	}

	public void GetDescription(String outStr)
	{
		outStr.Append("Set Transform");
	}
}

// ==================== Name Command ====================

/// Sets an entity's name. Captures old and new values for undo/redo.
class SetNameCommand : IEditorCommand
{
	private Scene mScene;
	private EntityId mEntity;
	private String mOldName ~ delete _;
	private String mNewName ~ delete _;

	public this(Scene scene, EntityId entity, StringView oldName, StringView newName)
	{
		mScene = scene;
		mEntity = entity;
		mOldName = new String(oldName);
		mNewName = new String(newName);
	}

	public void Execute()
	{
		mScene.SetName(mEntity, mNewName);
	}

	public void Undo()
	{
		mScene.SetName(mEntity, mOldName);
	}

	public void GetDescription(String outStr)
	{
		outStr.AppendF("Rename '{0}' → '{1}'", mOldName, mNewName);
	}
}

// ==================== Create Entity Command ====================

/// Creates an entity. Undo destroys it, redo recreates it.
class CreateEntityCommand : IEditorCommand
{
	private Scene mScene;
	private EntityId mEntity;
	private String mName ~ delete _;
	private bool mCreated = false;

	/// Use after creating the entity externally. The command takes ownership of undo/redo.
	public this(Scene scene, EntityId entity, StringView name)
	{
		mScene = scene;
		mEntity = entity;
		mName = new String(name);
		mCreated = true;
	}

	public EntityId Entity => mEntity;

	public void Execute()
	{
		if (!mCreated)
		{
			mEntity = mScene.CreateEntity();
			mScene.SetName(mEntity, mName);
			mCreated = true;
		}
	}

	public void Undo()
	{
		if (mCreated)
		{
			mScene.DestroyEntity(mEntity);
			mCreated = false;
		}
	}

	public void GetDescription(String outStr)
	{
		outStr.AppendF("Create '{0}'", mName);
	}
}

// ==================== Destroy Entity Command ====================

/// Destroys an entity. Captures name + transform for undo (recreate).
/// Note: Component data is NOT preserved across undo — only name and transform.
class DestroyEntityCommand : IEditorCommand
{
	private Scene mScene;
	private EntityId mEntity;
	private String mName ~ delete _;
	private Transform mTransform;
	private bool mDestroyed = false;

	public this(Scene scene, EntityId entity)
	{
		mScene = scene;
		mEntity = entity;
		mName = new String(scene.GetName(entity));
		mTransform = scene.GetTransform(entity);
	}

	public void Execute()
	{
		if (!mDestroyed)
		{
			mScene.DestroyEntity(mEntity);
			mDestroyed = true;
		}
	}

	public void Undo()
	{
		if (mDestroyed)
		{
			mEntity = mScene.CreateEntity();
			mScene.SetName(mEntity, mName);
			mScene.SetTransform(mEntity, mTransform);
			mDestroyed = false;
		}
	}

	public void GetDescription(String outStr)
	{
		outStr.AppendF("Delete '{0}'", mName);
	}
}
