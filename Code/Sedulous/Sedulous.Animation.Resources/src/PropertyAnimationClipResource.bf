using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Animation;

namespace Sedulous.Animation.Resources;

/// Resource wrapping a PropertyAnimationClip for the resource system.
class PropertyAnimationClipResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 5; // Next after Animation=4

	private PropertyAnimationClip mClip;
	private bool mOwnsClip;

	/// The underlying property animation clip data.
	public PropertyAnimationClip Clip => mClip;

	/// Duration of the animation in seconds.
	public float Duration => mClip?.Duration ?? 0;

	public this()
	{
		mClip = null;
		mOwnsClip = false;
	}

	public this(PropertyAnimationClip clip, bool ownsClip = false)
	{
		mClip = clip;
		mOwnsClip = ownsClip;
		if (clip != null && Name.IsEmpty)
			Name.Set(clip.Name);
	}

	public ~this()
	{
		if (mOwnsClip && mClip != null)
			delete mClip;
	}

	/// Sets the property animation clip. Takes ownership if ownsClip is true.
	public void SetClip(PropertyAnimationClip clip, bool ownsClip = false)
	{
		if (mOwnsClip && mClip != null)
			delete mClip;
		mClip = clip;
		mOwnsClip = ownsClip;
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => FileVersion;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mClip == null)
				return .InvalidData;

			mClip.Serialize(s);
		}
		else
		{
			let clip = new PropertyAnimationClip();
			clip.Serialize(s);
			SetClip(clip, true);
		}

		return .Ok;
	}

	/// Save this property animation resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mClip == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = FileType;
		writer.Int32("type", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a property animation resource from a file.
	public static Result<PropertyAnimationClipResource> LoadFromFile(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > FileVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("type", ref fileType);
		if (fileType != FileType)
			return .Err;

		let resource = new PropertyAnimationClipResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
