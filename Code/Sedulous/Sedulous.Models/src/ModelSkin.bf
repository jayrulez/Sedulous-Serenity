using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.Models;

/// Skin data for skeletal animation
public class ModelSkin
{
	private String mName ~ delete _;
	private List<int32> mJoints ~ delete _;
	private List<Matrix4x4> mInverseBindMatrices ~ delete _;

	/// Index of the skeleton root bone (-1 if not specified)
	public int32 SkeletonRootIndex = -1;

	public StringView Name => mName;
	public List<int32> Joints => mJoints;
	public List<Matrix4x4> InverseBindMatrices => mInverseBindMatrices;

	public this()
	{
		mName = new String();
		mJoints = new List<int32>();
		mInverseBindMatrices = new List<Matrix4x4>();
	}

	public void SetName(StringView name)
	{
		mName.Set(name);
	}

	/// Add a joint to the skin
	public void AddJoint(int32 boneIndex, Matrix4x4 inverseBindMatrix)
	{
		mJoints.Add(boneIndex);
		mInverseBindMatrices.Add(inverseBindMatrix);
	}
}
