namespace RenderMaterialsCustom;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using Sedulous.Imaging;

/// Custom materials sample demonstrating toon/cel-shading via a custom shader.
/// Uses MaterialBuilder to define toon material properties that map to a custom
/// toon.frag.hlsl shader, showcasing how to extend the render pipeline with
/// non-PBR shading models. Includes animated Fox with toon shading.
class RenderMaterialsCustomApp : Application
{
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mSphereMeshHandle;
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Fox (skinned mesh)
	private Model mFoxModel ~ delete _;
	private Skeleton mSkeleton ~ delete _;
	private AnimationPlayer mPlayer ~ delete _;
	private AnimationClip[] mClips ~ DeleteContainerAndItems!(_);
	private SkinnedMeshProxyHandle mFoxProxy;
	private GPUMeshHandle mFoxMeshHandle;
	private GPUBoneBufferHandle mBoneBufferHandle;
	private GPUTextureHandle mFoxTextureHandle;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;

	// Materials
	private Material mToonMaterial ~ delete _;
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

	// Camera
	private Vector3 mCameraPosition = .(0, 3, 10);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend) { }

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders", "shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{ Console.WriteLine("ERROR: Failed to initialize RenderSystem"); return; }

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		RegisterFeatures();
		CreateToonMaterial();
		CreateScene();
		CreateLights();
		LoadFoxModel();

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Materials Custom initialized");
		Console.WriteLine("  5 toon styles: Red, Blue, Green, Gold, Purple");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture, ESC: exit");
		Console.WriteLine("  Arrow keys: adjust light direction");
	}

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void CreateToonMaterial()
	{
		// Create base toon material definition using MaterialBuilder.
		// The property order here determines the cbuffer layout in toon.frag.hlsl:
		//   BaseColor (float4) at offset 0
		//   ShadowColor (float4) at offset 16
		//   RimColor (float4) at offset 32
		//   Bands (float) at offset 48
		//   RimPower (float) at offset 52
		//   RimIntensity (float) at offset 56
		//   ShadowThreshold (float) at offset 60
		mToonMaterial = scope MaterialBuilder("ToonMaterial")
			.Shader("toon")
			.VertexLayout(.Mesh)
			.Flags(.DefaultOpaque)
			.Color("BaseColor", .(1, 1, 1, 1))
			.Color("ShadowColor", .(0.3f, 0.1f, 0.1f, 1))
			.Color("RimColor", .(1, 0.9f, 0.8f, 1))
			.Float("Bands", 3.0f)
			.Float("RimPower", 3.0f)
			.Float("RimIntensity", 0.5f)
			.Float("ShadowThreshold", 0.3f)
			.Texture("AlbedoMap", null)
			.Sampler("LinearSampler", null)
			.Build();
	}

	private void CreateScene()
	{
		let sphereMesh = MeshBuilder.CreateSphere(0.8f, 32, 16);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let h)) mSphereMeshHandle = h;
		delete sphereMesh;

		let cubeMesh = MeshBuilder.CreateCube(1.2f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let h2)) mCubeMeshHandle = h2;
		delete cubeMesh;

		let planeMesh = MeshBuilder.CreatePlane(25.0f, 25.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let h3)) mPlaneMeshHandle = h3;
		delete planeMesh;

		if (mToonMaterial == null) return;

		// Floor — gray toon material
		let floorMat = new MaterialInstance(mToonMaterial);
		floorMat.SetColor("BaseColor", .(0.5f, 0.5f, 0.5f, 1));
		floorMat.SetColor("ShadowColor", .(0.15f, 0.15f, 0.2f, 1));
		floorMat.SetColor("RimColor", .(0, 0, 0, 0));
		floorMat.SetFloat("Bands", 3.0f);
		floorMat.SetFloat("RimIntensity", 0.0f);
		mMaterials.Add(floorMat);

		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = floorMat;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-12.5f, 0, -12.5f), Vector3(12.5f, 0.01f, 12.5f)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// 5 toon material styles
		Vector4[5] baseColors = .(
			.(0.9f, 0.2f, 0.15f, 1),   // Red
			.(0.2f, 0.3f, 0.9f, 1),    // Blue
			.(0.25f, 0.75f, 0.3f, 1),   // Green
			.(1.0f, 0.8f, 0.2f, 1),    // Gold
			.(0.6f, 0.2f, 0.85f, 1)    // Purple
		);
		Vector4[5] shadowColors = .(
			.(0.3f, 0.05f, 0.05f, 1),
			.(0.05f, 0.05f, 0.3f, 1),
			.(0.05f, 0.2f, 0.08f, 1),
			.(0.3f, 0.2f, 0.05f, 1),
			.(0.15f, 0.05f, 0.25f, 1)
		);
		Vector4[5] rimColors = .(
			.(1, 0.8f, 0.7f, 1),
			.(0.7f, 0.8f, 1, 1),
			.(0.8f, 1, 0.8f, 1),
			.(1, 0.95f, 0.7f, 1),
			.(1, 0.7f, 1, 1)
		);
		float[5] bands = .(3.0f, 2.0f, 5.0f, 4.0f, 3.0f);
		float[5] rimPowers = .(3.0f, 4.0f, 2.0f, 3.0f, 2.5f);
		float[5] rimIntensities = .(0.5f, 0.3f, 0.4f, 0.5f, 0.8f);
		float[5] shadowThresholds = .(0.3f, 0.5f, 0.2f, 0.3f, 0.3f);

		float spacing = 3.0f;
		float startX = -((5 - 1) * spacing) / 2.0f;

		for (int i = 0; i < 5; i++)
		{
			let mat = new MaterialInstance(mToonMaterial);
			mat.SetColor("BaseColor", baseColors[i]);
			mat.SetColor("ShadowColor", shadowColors[i]);
			mat.SetColor("RimColor", rimColors[i]);
			mat.SetFloat("Bands", bands[i]);
			mat.SetFloat("RimPower", rimPowers[i]);
			mat.SetFloat("RimIntensity", rimIntensities[i]);
			mat.SetFloat("ShadowThreshold", shadowThresholds[i]);
			mMaterials.Add(mat);

			float x = startX + i * spacing;

			// Sphere
			let sphere = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(sphere))
			{
				proxy.MeshHandle = mSphereMeshHandle;
				proxy.Materials[0] = mat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.8f, -0.8f, -0.8f), Vector3(0.8f, 0.8f, 0.8f)));
				proxy.SetTransformImmediate(Matrix.CreateTranslation(.(x, 0.5f, 0)));
				proxy.Flags = .DefaultOpaque;
			}

			// Small cube behind
			let cube = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(cube))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mat;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.6f, -0.6f, -0.6f), Vector3(0.6f, 0.6f, 0.6f)));
				proxy.SetTransformImmediate(Matrix.CreateScale(0.6f) * Matrix.CreateTranslation(.(x, 0.3f, -2.5f)));
				proxy.Flags = .DefaultOpaque;
			}
		}
	}

	private void CreateLights()
	{
		let lightDir = GetLightDirection();
		mSunLight = mWorld.CreateDirectionalLight(lightDir, .(1.0f, 0.98f, 0.95f), 2.5f);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// Fill light
		mWorld.CreatePointLight(.(-5, 3, 5), .(0.4f, 0.5f, 0.6f), 3.0f, 20.0f);
	}

	private Vector3 GetLightDirection()
	{
		float cosP = Math.Cos(mLightPitch);
		return Vector3.Normalize(.(
			Math.Sin(mLightYaw) * cosP,
			Math.Sin(mLightPitch),
			Math.Cos(mLightYaw) * cosP
		));
	}

	private void UpdateLightDirection()
	{
		if (let light = mWorld.GetLight(mSunLight))
			light.Direction = GetLightDirection();
	}

	// ==================== Fox Model ====================

	private void LoadFoxModel()
	{
		GltfModels.Initialize();

		let modelPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Fox.gltf";
		mFoxModel = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, mFoxModel) != .Ok)
		{
			Console.WriteLine("Warning: Failed to load Fox model");
			delete mFoxModel;
			mFoxModel = null;
			return;
		}

		if (mFoxModel.Skins.Count == 0) return;

		let skin = mFoxModel.Skins[0];
		int32 meshIndex = -1;
		for (let bone in mFoxModel.Bones)
		{
			if (bone.SkinIndex == 0)
			{
				meshIndex = bone.MeshIndex;
				break;
			}
		}

		if (meshIndex < 0 || meshIndex >= mFoxModel.Meshes.Count) return;

		let modelMesh = mFoxModel.Meshes[meshIndex];
		if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin) case .Ok(var convResult))
		{
			defer convResult.Dispose();
			let skinnedMesh = convResult.Mesh;
			defer delete skinnedMesh;

			if (mRenderSystem.ResourceManager.UploadMesh(skinnedMesh) case .Ok(let gpuHandle))
			{
				mFoxMeshHandle = gpuHandle;
				let boneCount = (uint16)skin.Joints.Count;

				if (mRenderSystem.ResourceManager.CreateBoneBuffer(boneCount) case .Ok(let boneHandle))
				{
					mBoneBufferHandle = boneHandle;
					BuildSkeleton(skin);
					ExtractAnimations();
					LoadFoxTexture();

					// Create fox toon material — white base with orange shadow, texture provides color
					if (mToonMaterial != null)
					{
						let foxMat = new MaterialInstance(mToonMaterial);
						foxMat.SetColor("BaseColor", .(1, 1, 1, 1));
						foxMat.SetColor("ShadowColor", .(0.3f, 0.15f, 0.1f, 1));
						foxMat.SetColor("RimColor", .(1, 0.9f, 0.7f, 1));
						foxMat.SetFloat("Bands", 3.0f);
						foxMat.SetFloat("RimPower", 2.5f);
						foxMat.SetFloat("RimIntensity", 0.4f);
						foxMat.SetFloat("ShadowThreshold", 0.3f);
						if (mFoxTextureHandle.IsValid)
						{
							if (let texView = mRenderSystem.ResourceManager.GetTextureView(mFoxTextureHandle))
								foxMat.SetTexture("AlbedoMap", texView);
						}
						mMaterials.Add(foxMat);

						// Position fox to the right of the toon objects
						mFoxProxy = mWorld.CreateSkinnedMesh();
						if (let proxy = mWorld.GetSkinnedMesh(mFoxProxy))
						{
							proxy.MeshHandle = mFoxMeshHandle;
							proxy.BoneBufferHandle = mBoneBufferHandle;
							proxy.Materials[0] = foxMat;
							proxy.MaterialCount = 1;
							proxy.SetLocalBounds(skinnedMesh.Bounds);
							proxy.BoneCount = boneCount;
							proxy.SetTransformImmediate(Matrix.CreateScale(0.03f) * Matrix.CreateTranslation(.(8, 0, 0)));
							proxy.Flags = .DefaultOpaque;
						}
					}

					if (mClips != null && mClips.Count > 0)
					{
						mClips[0].IsLooping = true;
						mPlayer.Play(mClips[0]);
						Console.WriteLine("  Fox playing: {}", mClips[0].Name);
					}
				}
			}
		}
	}

	private void BuildSkeleton(ModelSkin skin)
	{
		let jointCount = (int32)skin.Joints.Count;
		mSkeleton = new Skeleton(jointCount);

		Dictionary<int32, int32> boneToJoint = scope .();
		for (int32 j = 0; j < jointCount; j++)
			boneToJoint[skin.Joints[j]] = j;

		for (int32 j = 0; j < jointCount; j++)
		{
			let boneIndex = skin.Joints[j];
			let modelBone = mFoxModel.Bones[boneIndex];
			let bone = mSkeleton.Bones[j];

			bone.Name.Set(modelBone.Name);
			bone.Index = j;

			if (modelBone.ParentIndex >= 0 && boneToJoint.TryGetValue(modelBone.ParentIndex, let parentJoint))
				bone.ParentIndex = parentJoint;
			else
				bone.ParentIndex = -1;

			bone.LocalBindPose = Transform(modelBone.Translation, modelBone.Rotation, modelBone.Scale);

			if (j < skin.InverseBindMatrices.Count)
				bone.InverseBindPose = skin.InverseBindMatrices[j];
		}

		mSkeleton.BuildNameMap();
		mSkeleton.FindRootBones();
		mSkeleton.BuildChildIndices();
		mPlayer = new AnimationPlayer(mSkeleton);
	}

	private void ExtractAnimations()
	{
		if (mFoxModel.Animations.Count == 0)
		{
			mClips = new AnimationClip[0];
			return;
		}

		let skin = mFoxModel.Skins[0];
		Dictionary<int32, int32> boneToJoint = scope .();
		for (int32 j = 0; j < (int32)skin.Joints.Count; j++)
			boneToJoint[skin.Joints[j]] = j;

		mClips = new AnimationClip[mFoxModel.Animations.Count];
		for (int i = 0; i < mFoxModel.Animations.Count; i++)
		{
			let modelAnim = mFoxModel.Animations[i];
			let clip = new AnimationClip(modelAnim.Name, modelAnim.Duration, false);

			for (let channel in modelAnim.Channels)
			{
				int32 jointIndex;
				if (!boneToJoint.TryGetValue(channel.TargetBone, out jointIndex))
					continue;

				let interp = ConvertInterpolation(channel.Interpolation);

				switch (channel.Path)
				{
				case .Translation:
					let track = clip.GetOrCreatePositionTrack(jointIndex);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				case .Rotation:
					let track = clip.GetOrCreateRotationTrack(jointIndex);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Quaternion(kf.Value.X, kf.Value.Y, kf.Value.Z, kf.Value.W));
				case .Scale:
					let track = clip.GetOrCreateScaleTrack(jointIndex);
					track.Interpolation = interp;
					for (let kf in channel.Keyframes)
						track.AddKeyframe(kf.Time, Vector3(kf.Value.X, kf.Value.Y, kf.Value.Z));
				case .Weights:
					continue;
				}
			}

			clip.SortAllKeyframes();
			clip.ComputeDuration();
			mClips[i] = clip;
		}
	}

	private static InterpolationMode ConvertInterpolation(AnimationInterpolation interp)
	{
		switch (interp)
		{
		case .Step: return .Step;
		case .Linear: return .Linear;
		case .CubicSpline: return .CubicSpline;
		}
	}

	private void LoadFoxTexture()
	{
		let texPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Texture.png";
		if (ImageLoaderFactory.LoadImage(texPath) case .Ok(var image))
		{
			defer delete image;
			let texData = TextureData.FromImage(image);
			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
				mFoxTextureHandle = texHandle;
		}
	}

	// ==================== Input / Update / Render ====================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();
		if (keyboard.IsKeyPressed(.Tab))
		{ mMouseCaptured = !mMouseCaptured; mouse.RelativeMode = mMouseCaptured; mouse.Visible = !mMouseCaptured; }
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{ mYaw += mouse.DeltaX * 0.003f; mPitch -= mouse.DeltaY * 0.003f; mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f); }
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? 20.0f : 10.0f;
		float cosP = Math.Cos(mPitch);
		Vector3 forward = .(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw));
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
		Vector3 move = .Zero;
		if (keyboard.IsKeyDown(.W)) move += forward;
		if (keyboard.IsKeyDown(.S)) move -= forward;
		if (keyboard.IsKeyDown(.D)) move += right;
		if (keyboard.IsKeyDown(.A)) move -= right;
		if (keyboard.IsKeyDown(.E)) move += .(0, 1, 0);
		if (keyboard.IsKeyDown(.Q)) move -= .(0, 1, 0);
		if (move.LengthSquared() > 0) mCameraPosition += Vector3.Normalize(move) * speed * dt;

		// Light direction control with arrow keys
		float lightSpeed = 1.0f * dt;
		bool lightChanged = false;
		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);
		if (lightChanged) UpdateLightDirection();

		// Update fox animation
		if (mPlayer != null)
		{
			mPlayer.Update(dt);
			mPlayer.Evaluate();

			if (mBoneBufferHandle.IsValid)
			{
				let currentMatrices = mPlayer.GetSkinningMatrices();
				let prevMatrices = mPlayer.GetPrevSkinningMatrices();
				mRenderSystem.ResourceManager.UpdateBoneBuffer(
					mBoneBufferHandle,
					currentMatrices.Ptr,
					prevMatrices.Ptr,
					(uint16)mSkeleton.BoneCount
				);
			}
		}

		// Debug drawing
		UpdateDebugDrawing(dt);

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	private void UpdateDebugDrawing(float dt)
	{
		if (mOverlayFeature == null) return;

		// FPS
		let fps = (dt > 0) ? (1.0f / dt) : 0;
		let fpsText = scope String();
		fpsText.AppendF("FPS: {0:0.0}", fps);
		mOverlayFeature.AddText2D(fpsText, 10, 10, .(255, 255, 0, 255), 2.0f);

		// Light direction visualization
		let lightDir = GetLightDirection();
		let lightStart = Vector3(0, 5, 0);
		let lightEnd = lightStart + lightDir * 5.0f;

		mOverlayFeature.AddAxes(lightStart, 1.5f, .Overlay);
		mOverlayFeature.AddLine(lightStart, lightEnd, .(255, 255, 0, 255), .Overlay);

		// Arrow head
		let arrowRight = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let arrowUp = Vector3.Normalize(Vector3.Cross(arrowRight, lightDir));
		let arrowSize = 0.3f;
		let arrowColor = Color(255, 128, 0, 255);

		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + arrowRight * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - arrowRight * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + arrowUp * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - arrowUp * arrowSize * 0.5f, arrowColor, .Overlay);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		if (mFinalOutputFeature != null) mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mCameraPosition, mCameraForward, .(0, 1, 0), mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok) mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mSphereMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);
		if (mCubeMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);
		if (mFoxMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFoxMeshHandle, mRenderSystem.FrameNumber);
		if (mBoneBufferHandle.IsValid) mRenderSystem.ResourceManager.ReleaseBoneBuffer(mBoneBufferHandle, mRenderSystem.FrameNumber);
		if (mFoxTextureHandle.IsValid) mRenderSystem.ResourceManager.ReleaseTexture(mFoxTextureHandle, mRenderSystem.FrameNumber);
		mRenderSystem?.Shutdown();
		Console.WriteLine("Render Materials Custom shutting down");
	}
}
