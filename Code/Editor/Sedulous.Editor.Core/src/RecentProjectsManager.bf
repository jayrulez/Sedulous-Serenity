namespace Sedulous.Editor.Core;

using System;
using System.Collections;
using System.IO;

/// Information about a recent project.
public class RecentProject
{
	public String Name ~ delete _;
	public String Path ~ delete _;
	public DateTime LastOpened;

	public this()
	{
		Name = new .();
		Path = new .();
	}

	public this(StringView name, StringView path)
	{
		Name = new .(name);
		Path = new .(path);
		LastOpened = DateTime.Now;
	}
}

/// Manages the list of recently opened projects.
/// Persists the list to a file in the user's app data directory.
public class RecentProjectsManager
{
	private List<RecentProject> mProjects = new .() ~ DeleteContainerAndItems!(_);
	private String mSettingsPath = new .() ~ delete _;
	private int mMaxProjects;

	/// All recent projects (most recent first).
	public List<RecentProject> Projects => mProjects;

	/// Number of recent projects.
	public int Count => mProjects.Count;

	/// Creates a recent projects manager.
	/// @param settingsDirectory Directory to store the settings file.
	/// @param maxProjects Maximum number of recent projects to track.
	public this(StringView settingsDirectory, int maxProjects = 10)
	{
		mMaxProjects = maxProjects;
		Path.InternalCombine(mSettingsPath, settingsDirectory, "recent_projects.txt");

		// Ensure directory exists
		if (!Directory.Exists(settingsDirectory))
			Directory.CreateDirectory(settingsDirectory);

		Load();
	}

	/// Add or update a project in the recent list.
	/// Moves the project to the top if already in the list.
	public void AddProject(StringView name, StringView path)
	{
		// Check if already in list
		for (int i = 0; i < mProjects.Count; i++)
		{
			if (mProjects[i].Path == path)
			{
				// Move to front
				let existing = mProjects[i];
				existing.LastOpened = DateTime.Now;
				mProjects.RemoveAt(i);
				mProjects.Insert(0, existing);
				Save();
				return;
			}
		}

		// Add new project at front
		let project = new RecentProject(name, path);
		mProjects.Insert(0, project);

		// Trim if over limit
		while (mProjects.Count > mMaxProjects)
		{
			let removed = mProjects.PopBack();
			delete removed;
		}

		Save();
	}

	/// Remove a project from the recent list.
	public void RemoveProject(StringView path)
	{
		for (int i = 0; i < mProjects.Count; i++)
		{
			if (mProjects[i].Path == path)
			{
				let removed = mProjects[i];
				mProjects.RemoveAt(i);
				delete removed;
				Save();
				return;
			}
		}
	}

	/// Clear all recent projects.
	public void Clear()
	{
		DeleteContainerAndItems!(mProjects);
		mProjects = new .();
		Save();
	}

	/// Check if a project path exists in the recent list.
	public bool Contains(StringView path)
	{
		for (let project in mProjects)
		{
			if (project.Path == path)
				return true;
		}
		return false;
	}

	/// Load recent projects from disk.
	private void Load()
	{
		if (!File.Exists(mSettingsPath))
			return;

		let content = scope String();
		if (File.ReadAllText(mSettingsPath, content) case .Err)
			return;

		// Simple text format: each line is "name|path|timestamp"
		for (let line in content.Split('\n'))
		{
			let trimmed = scope String(line);
			trimmed.Trim();
			if (trimmed.IsEmpty)
				continue;

			let parts = trimmed.Split('|');
			String name = null;
			String path = null;
			int64 ticks = 0;

			int partIndex = 0;
			for (let part in parts)
			{
				switch (partIndex)
				{
				case 0: name = scope:: String(part);
				case 1: path = scope:: String(part);
				case 2:
					if (Int64.Parse(part) case .Ok(let val))
						ticks = val;
				}
				partIndex++;
			}

			if (name != null && path != null && !path.IsEmpty)
			{
				let project = new RecentProject();
				project.Name.Set(name);
				project.Path.Set(path);
				project.LastOpened = DateTime(ticks);
				mProjects.Add(project);
			}
		}
	}

	/// Save recent projects to disk.
	private void Save()
	{
		let content = scope String();

		for (let project in mProjects)
		{
			content.AppendF("{0}|{1}|{2}\n", project.Name, project.Path, project.LastOpened.Ticks);
		}

		File.WriteAllText(mSettingsPath, content).IgnoreError();
	}
}
