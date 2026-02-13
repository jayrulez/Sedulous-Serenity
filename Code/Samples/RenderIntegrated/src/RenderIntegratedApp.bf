namespace RenderIntegrated;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using Sedulous.Imaging;

/// Full integration demo combining all render features:
/// - 8x8 cube grid with PBR materials
/// - Skinned mesh (Fox) with animation cycling
/// - Particle effects (fire, smoke, fountain, sparkles)
/// - Sprite billboards
/// - Standalone trail emitter
/// - Debug drawing (wireframes, axes, grid, text)
/// - Interactive lighting
class RenderIntegratedApp : Application
{
	private const int32 GRID_SIZE = 8;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private OverlayRenderFeature mOverlayFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Mesh handles
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mFloorMeshHandle;
	private GPUMeshHandle mFoxMeshHandle;
	private GPUBoneBufferHandle mBoneBufferHandle;
	private GPUTextureHandle mFoxTextureHandle;

	// Materials
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

	// Fox (skinned mesh)
	private Model mFoxModel ~ delete _;
	private Skeleton mSkeleton ~ delete _;
	private AnimationPlayer mPlayer ~ delete _;
	private AnimationClip[] mClips ~ DeleteContainerAndItems!(_);
	private SkinnedMeshProxyHandle mFoxProxy;
	private int32 mCurrentAnimIndex = 0;

	// Particle emitters
	private ParticleEmitterProxyHandle mFireEmitter;
	private ParticleEmitterProxyHandle mSmokeEmitter;
	private ParticleEmitterProxyHandle mFountainEmitter;
	private ParticleEmitterProxyHandle mSparkleEmitter;
	private ParticleEmitterProxyHandle mSnowEmitter;
	private ParticleEmitterProxyHandle[4] mTorchEmitters;
	private ParticleEmitterProxyHandle mMagicCoreEmitter;
	private ParticleEmitterProxyHandle mMagicSwirlEmitter;
	private ParticleEmitterProxyHandle mMagicSparkleEmitter;
	private ParticleEmitterProxyHandle mMagicWispEmitter;
	private ParticleEmitterProxyHandle mHealEmitter;
	private ParticleEmitterProxyHandle mSparksEmitter;
	private ParticleEmitterProxyHandle mFairyEmitter;
	private ParticleEmitterProxyHandle mSteamEmitter;
	private ParticleEmitterProxyHandle mTrailedSparksEmitter;
	private ParticleEmitterProxyHandle mForceFieldDustEmitter;
	private ParticleEmitterProxyHandle mFireworkEmitter;
	private ParticleEmitterProxyHandle mFireworkExplosionEmitter;
	private float mFireworkTimer = 0;

	// Particle effect labels for debug visualization
	private struct ParticleEffectLabel
	{
		public Vector3 Position;
		public Color MarkerColor;
		public String Name;

		public this(Vector3 pos, Color color, String name)
		{
			Position = pos;
			MarkerColor = color;
			Name = name;
		}
	}
	private List<ParticleEffectLabel> mParticleLabels = new .() ~ delete _;

	// Sprites
	private List<SpriteProxyHandle> mSprites = new .() ~ delete _;

	// Trail emitters
	private TrailEmitterProxyHandle mTrailHandle;
	private TrailEmitterProxyHandle mSwordTrailHandle;
	private float mTrailAngle = 0;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;
	private float mLightIntensity = 2.0f;

	// Camera
	private Vector3 mCameraPosition = .(0, 10, 30);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.3f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 500.0f;

		RegisterFeatures();
		CreateMeshes();
		CreateCubeGrid();
		CreateFloor();
		CreateLights();
		CreateParticles();
		CreateSprites();
		CreateTrail();
		LoadFoxModel();

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Integrated initialized");
		Console.WriteLine($"  {GRID_SIZE * GRID_SIZE} cubes, particles, sprites, fox, trails, debug");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture");
		Console.WriteLine("  Space: cycle Fox anims, Arrow keys: light direction");
		Console.WriteLine("  Z/X: light intensity, ESC: exit");
	}

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mTransparentFeature = new ForwardTransparentFeature();
		mRenderSystem.RegisterFeature(mTransparentFeature);

		mParticleFeature = new ParticleFeature();
		mRenderSystem.RegisterFeature(mParticleFeature);

		mSpriteFeature = new SpriteFeature();
		mRenderSystem.RegisterFeature(mSpriteFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void CreateMeshes()
	{
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let h))
			mCubeMeshHandle = h;
		delete cubeMesh;

		let planeMesh = StaticMesh.CreatePlane(50.0f, 50.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let h2))
			mFloorMeshHandle = h2;
		delete planeMesh;
	}

	private void CreateFloor()
	{
		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mFloorMeshHandle;
			proxy.Materials[0] = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-25, 0, -25), Vector3(25, 0.01f, 25)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(0, -0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateCubeGrid()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null) return;

		// 8 cube colors
		Vector4[8] cubeColors = .(
			.(1.0f, 0.3f, 0.3f, 1.0f),
			.(0.3f, 1.0f, 0.3f, 1.0f),
			.(0.3f, 0.3f, 1.0f, 1.0f),
			.(1.0f, 1.0f, 0.3f, 1.0f),
			.(1.0f, 0.3f, 1.0f, 1.0f),
			.(0.3f, 1.0f, 1.0f, 1.0f),
			.(1.0f, 0.6f, 0.3f, 1.0f),
			.(0.6f, 0.3f, 1.0f, 1.0f)
		);

		// Create 8 material instances
		for (int i = 0; i < 8; i++)
		{
			let mat = new MaterialInstance(baseMat);
			mat.SetColor("BaseColor", cubeColors[i]);
			mat.SetFloat("Metallic", 0.2f);
			mat.SetFloat("Roughness", 0.5f);
			mMaterials.Add(mat);
		}

		// Create grid of cubes
		float spacing = 3.0f;
		float startOffset = -(GRID_SIZE * spacing) / 2.0f;

		for (int32 x = 0; x < GRID_SIZE; x++)
		{
			for (int32 z = 0; z < GRID_SIZE; z++)
			{
				float posX = startOffset + x * spacing;
				float posZ = startOffset + z * spacing;

				let cube = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(cube))
				{
					proxy.MeshHandle = mCubeMeshHandle;
					proxy.Materials[0] = mMaterials[(x + z) % 8];
					proxy.MaterialCount = 1;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
					proxy.SetTransformImmediate(Matrix.CreateTranslation(.(posX, 0.5f, posZ)));
					proxy.Flags = .DefaultOpaque;
				}
			}
		}
	}

	private void CreateLights()
	{
		UpdateSunLight();
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// 8 random point lights
		Random rng = scope .(12345);
		for (int i = 0; i < 8; i++)
		{
			float px = ((float)rng.NextDouble() - 0.5f) * 30.0f;
			float py = (float)rng.NextDouble() * 5.0f + 2.0f;
			float pz = ((float)rng.NextDouble() - 0.5f) * 30.0f;
			Vector3 color = .(
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f
			);
			mWorld.CreatePointLight(.(px, py, pz), color, 5.0f, 15.0f);
		}
	}

	private void UpdateSunLight()
	{
		float cosP = Math.Cos(mLightPitch);
		let dir = Vector3.Normalize(.(
			Math.Sin(mLightYaw) * cosP,
			Math.Sin(mLightPitch),
			Math.Cos(mLightYaw) * cosP
		));

		if (!mSunLight.IsValid)
		{
			mSunLight = mWorld.CreateDirectionalLight(dir, .(1.0f, 0.95f, 0.8f), mLightIntensity);
			if (let light = mWorld.GetLight(mSunLight)) light.CastsShadows = true;
		}
		else if (let light = mWorld.GetLight(mSunLight))
		{
			light.Direction = dir;
			light.Intensity = mLightIntensity;
		}
	}

	private void RegisterEffect(Vector3 pos, Color color, String name)
	{
		mParticleLabels.Add(.(pos, color, name));
	}

	private void CreateParticles()
	{
		// ==================== FIRE PIT ====================
		mFireEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mFireEmitter))
		{

			e.Position = .(0, 0.2f, -15);
			e.MaxParticles = 500;
			e.SpawnRate = 80.0f;
			e.ParticleLifetime = 1.0f;
			e.StartSize = .(0.3f, 0.5f);
			e.EndSize = .(0.5f, 0.8f);
			e.StartColor = .(1.0f, 0.8f, 0.2f, 1.0f);
			e.EndColor = .(0.8f, 0.2f, 0.0f, 0.0f);
			e.InitialVelocity = .(0, 3.0f, 0);
			e.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
			e.GravityMultiplier = -0.3f;
			e.BlendMode = .Additive;
			e.IsEmitting = true;
		}
		RegisterEffect(.(0, 0.2f, -15), .(255, 100, 0, 255), "FIRE");

		// ==================== TORCH FIRES AT CORNERS ====================
		Vector3[4] torchPositions = .(
			.(-18, 2.0f, -18),
			.(18, 2.0f, -18),
			.(-18, 2.0f, 18),
			.(18, 2.0f, 18)
		);
		for (int i = 0; i < 4; i++)
		{
			mTorchEmitters[i] = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mTorchEmitters[i]))
			{
	
				e.Position = torchPositions[i];
				e.MaxParticles = 150;
				e.SpawnRate = 25.0f;
				e.ParticleLifetime = 0.8f;
				e.StartSize = .(0.15f, 0.3f);
				e.EndSize = .(0.3f, 0.5f);
				e.StartColor = .(1.0f, 0.7f, 0.2f, 1.0f);
				e.EndColor = .(0.8f, 0.2f, 0.0f, 0.0f);
				e.InitialVelocity = .(0, 2.5f, 0);
				e.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
				e.GravityMultiplier = -0.2f;
				e.BlendMode = .Additive;
				e.IsEmitting = true;
			}
			RegisterEffect(torchPositions[i], .(255, 150, 50, 255), "TORCH");
		}

		// ==================== SMOKE (with soft particles) ====================
		mSmokeEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mSmokeEmitter))
		{

			e.Position = .(0, 2.0f, -15);
			e.MaxParticles = 150;
			e.SpawnRate = 12.0f;
			e.ParticleLifetime = 4.0f;
			e.StartSize = .(0.6f, 1.0f);
			e.EndSize = .(2.0f, 3.0f);
			e.StartColor = .(0.5f, 0.5f, 0.5f, 0.4f);
			e.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
			e.InitialVelocity = .(0.3f, 1.0f, 0);
			e.VelocityRandomness = .(0.2f, 0.2f, 0.2f);
			e.GravityMultiplier = -0.1f;
			e.Drag = 0.4f;
			e.SoftParticleDistance = 0.8f;
			e.ForceModules.WindForce = .(0.3f, 0, 0.2f);
			e.ForceModules.WindTurbulence = 0.2f;
			e.IsEmitting = true;
		}
		RegisterEffect(.(0, 3.0f, -15), .(128, 128, 128, 255), "SMOKE (soft)");

		// ==================== MAGIC ORB - MULTI-LAYER EFFECT ====================
		let magicOrbPos = Vector3(12, 2.5f, 0);

		// Layer 1: Core Glow
		mMagicCoreEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mMagicCoreEmitter))
		{

			e.Position = magicOrbPos;
			e.MaxParticles = 40;
			e.SpawnRate = 20.0f;
			e.ParticleLifetime = 0.4f;
			e.StartSize = .(0.3f, 0.6f);
			e.EndSize = .(0.4f, 0.7f);
			e.StartColor = .(1.0f, 1.0f, 1.0f, 1.0f);
			e.EndColor = .(0.4f, 0.8f, 1.0f, 0.0f);
			e.InitialVelocity = .(0, 0, 0);
			e.VelocityRandomness = .(0.1f, 0.1f, 0.1f);
			e.GravityMultiplier = 0;
			e.BlendMode = .Additive;
			e.IsEmitting = true;
		}

		// Layer 2: Swirling Ring
		mMagicSwirlEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mMagicSwirlEmitter))
		{

			e.Position = magicOrbPos;
			e.MaxParticles = 80;
			e.SpawnRate = 25.0f;
			e.ParticleLifetime = 2.0f;
			e.StartSize = .(0.1f, 0.18f);
			e.EndSize = .(0.05f, 0.1f);
			e.StartColor = .(0.3f, 0.8f, 1.0f, 1.0f);
			e.EndColor = .(0.6f, 0.4f, 1.0f, 0.0f);
			e.InitialVelocity = .(0, 0, 0);
			e.VelocityRandomness = .(0.2f, 0.1f, 0.2f);
			e.GravityMultiplier = 0;
			e.Drag = 0.5f;
			e.BlendMode = .Additive;
			e.ForceModules.VortexStrength = 12.0f;
			e.ForceModules.VortexAxis = .(0, 1, 0);
			e.ForceModules.AttractorPosition = magicOrbPos;
			e.ForceModules.AttractorStrength = 3.0f;
			e.ForceModules.AttractorRadius = 2.0f;
			e.IsEmitting = true;
		}

		// Layer 3: Floating Sparkles
		mMagicSparkleEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mMagicSparkleEmitter))
		{

			e.Position = magicOrbPos;
			e.MaxParticles = 50;
			e.SpawnRate = 8.0f;
			e.ParticleLifetime = 2.5f;
			e.StartSize = .(0.04f, 0.1f);
			e.EndSize = .(0.0f, 0.02f);
			e.StartColor = .(0.6f, 0.7f, 1.0f, 0.8f);
			e.EndColor = .(0.7f, 0.4f, 1.0f, 0.0f);
			e.InitialVelocity = .(0, 0.3f, 0);
			e.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
			e.GravityMultiplier = 0;
			e.BlendMode = .Additive;
			e.ForceModules.TurbulenceStrength = 0.5f;
			e.ForceModules.TurbulenceFrequency = 1.0f;
			e.IsEmitting = true;
		}

		// Layer 4: Energy Wisps with Trails
		mMagicWispEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mMagicWispEmitter))
		{

			e.Position = magicOrbPos;
			e.MaxParticles = 6;
			e.SpawnRate = 2.0f;
			e.ParticleLifetime = 3.0f;
			e.StartSize = .(0.12f, 0.18f);
			e.EndSize = .(0.07f, 0.1f);
			e.StartColor = .(0.8f, 0.95f, 1.0f, 1.0f);
			e.EndColor = .(0.4f, 0.7f, 1.0f, 0.2f);
			e.InitialVelocity = .(0, 0, 0);
			e.VelocityRandomness = .(0.3f, 0.1f, 0.3f);
			e.GravityMultiplier = 0;
			e.Drag = 0.3f;
			e.BlendMode = .Additive;
			e.ForceModules.VortexStrength = 10.0f;
			e.ForceModules.VortexAxis = .(0, 1, 0);
			e.ForceModules.AttractorPosition = magicOrbPos;
			e.ForceModules.AttractorStrength = 2.5f;
			e.ForceModules.AttractorRadius = 1.5f;
			// Per-particle trails
			e.Trail.Enabled = true;
			e.Trail.MaxPoints = 30;
			e.Trail.RecordInterval = 0.03f;
			e.Trail.Lifetime = 0.8f;
			e.Trail.WidthStart = 0.1f;
			e.Trail.WidthEnd = 0.0f;
			e.Trail.UseParticleColor = true;
			e.IsEmitting = true;
		}

		RegisterEffect(magicOrbPos, .(150, 100, 255, 255), "MAGIC ORB");

		// ==================== HEALING MAGIC ====================
		{
			let pos = Vector3(-10, 0.5f, 8);
			mHealEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mHealEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 180;
				e.SpawnRate = 30.0f;
				e.ParticleLifetime = 2.0f;
				e.StartSize = .(0.06f, 0.12f);
				e.EndSize = .(0.02f, 0.04f);
				e.StartColor = .(0.2f, 1.0f, 0.4f, 1.0f);
				e.EndColor = .(0.4f, 1.0f, 0.6f, 0.0f);
				e.InitialVelocity = .(0, 0.5f, 0);
				e.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
				e.GravityMultiplier = 0;
				e.BlendMode = .Additive;
				e.ForceModules.AttractorPosition = pos + .(0, 1.0f, 0);
				e.ForceModules.AttractorStrength = 2.0f;
				e.ForceModules.AttractorRadius = 3.0f;
				e.ForceModules.VortexStrength = 2.0f;
				e.ForceModules.VortexAxis = .(0, 1, 0);
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(50, 255, 100, 255), "HEAL");
		}

		// ==================== SPARKS ====================
		{
			let pos = Vector3(10, 1.0f, -8);
			mSparksEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mSparksEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 300;
				e.SpawnRate = 60.0f;
				e.ParticleLifetime = 0.8f;
				e.StartSize = .(0.03f, 0.06f);
				e.EndSize = .(0.01f, 0.02f);
				e.StartColor = .(1.0f, 0.9f, 0.3f, 1.0f);
				e.EndColor = .(1.0f, 0.4f, 0.0f, 0.0f);
				e.InitialVelocity = .(0, 5.0f, 0);
				e.VelocityRandomness = .(3.0f, 2.0f, 3.0f);
				e.GravityMultiplier = 2.0f;
				e.BlendMode = .Additive;
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(255, 255, 100, 255), "SPARKS");
		}

		// ==================== WATER FOUNTAIN ====================
		mFountainEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mFountainEmitter))
		{

			e.Position = .(-12, 0.5f, -8);
			e.MaxParticles = 500;
			e.SpawnRate = 100.0f;
			e.ParticleLifetime = 2.5f;
			e.StartSize = .(0.08f, 0.15f);
			e.EndSize = .(0.05f, 0.08f);
			e.StartColor = .(0.4f, 0.7f, 1.0f, 0.9f);
			e.EndColor = .(0.2f, 0.5f, 0.8f, 0.0f);
			e.InitialVelocity = .(0, 10.0f, 0);
			e.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
			e.GravityMultiplier = 1.5f;
			e.IsEmitting = true;
		}
		RegisterEffect(.(-12, 0.5f, -8), .(100, 180, 255, 255), "FOUNTAIN");

		// ==================== SNOW ====================
		mSnowEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let e = mWorld.GetParticleEmitter(mSnowEmitter))
		{

			e.Position = .(8, 12, 10);
			e.MaxParticles = 350;
			e.SpawnRate = 35.0f;
			e.ParticleLifetime = 6.0f;
			e.StartSize = .(0.05f, 0.12f);
			e.EndSize = .(0.04f, 0.08f);
			e.StartColor = .(1.0f, 1.0f, 1.0f, 0.8f);
			e.EndColor = .(0.8f, 0.8f, 0.9f, 0.0f);
			e.InitialVelocity = .(0.5f, -0.5f, 0.2f);
			e.VelocityRandomness = .(0.8f, 0.2f, 0.8f);
			e.GravityMultiplier = 0.1f;
			e.Drag = 0.3f;
			e.ForceModules.WindForce = .(1.5f, 0, 0.5f);
			e.ForceModules.WindTurbulence = 0.8f;
			e.IsEmitting = true;
		}
		RegisterEffect(.(8, 8, 10), .(255, 255, 255, 255), "SNOW");

		// ==================== FAIRY DUST / FIREFLIES ====================
		{
			let pos = Vector3(-8, 1.5f, 12);
			mFairyEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mFairyEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 120;
				e.SpawnRate = 20.0f;
				e.ParticleLifetime = 4.0f;
				e.StartSize = .(0.08f, 0.15f);
				e.EndSize = .(0.12f, 0.22f);
				e.StartColor = .(1.0f, 0.86f, 0.4f, 1.0f);
				e.EndColor = .(1.0f, 0.7f, 0.2f, 0.0f);
				e.InitialVelocity = .(0, 0.1f, 0);
				e.VelocityRandomness = .(0.6f, 0.3f, 0.6f);
				e.GravityMultiplier = 0;
				e.Drag = 0.5f;
				e.BlendMode = .Additive;
				e.ForceModules.VortexStrength = 0.8f;
				e.ForceModules.VortexAxis = .(0, 1, 0);
				e.ForceModules.TurbulenceStrength = 0.3f;
				e.ForceModules.TurbulenceFrequency = 0.5f;
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(255, 220, 100, 255), "FIREFLIES");
		}

		// ==================== STEAM / MIST (with soft particles) ====================
		{
			let pos = Vector3(0, 0.1f, 10);
			mSteamEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mSteamEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 180;
				e.SpawnRate = 25.0f;
				e.ParticleLifetime = 3.0f;
				e.StartSize = .(0.3f, 0.6f);
				e.EndSize = .(1.5f, 2.5f);
				e.StartColor = .(0.94f, 0.94f, 1.0f, 0.7f);
				e.EndColor = .(0.8f, 0.8f, 0.86f, 0.0f);
				e.InitialVelocity = .(0, 3.0f, 0);
				e.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
				e.GravityMultiplier = -0.15f;
				e.Drag = 0.4f;
				e.SoftParticleDistance = 1.0f;
				e.ForceModules.TurbulenceStrength = 1.2f;
				e.ForceModules.TurbulenceFrequency = 0.8f;
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(200, 200, 255, 255), "STEAM (soft)");
		}

		// ==================== PER-PARTICLE TRAILS ====================
		{
			let pos = Vector3(15, 3, 10);
			mTrailedSparksEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mTrailedSparksEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 50;
				e.SpawnRate = 8.0f;
				e.ParticleLifetime = 2.5f;
				e.StartSize = .(0.1f, 0.2f);
				e.EndSize = .(0.05f, 0.1f);
				e.StartColor = .(1.0f, 0.8f, 0.2f, 1.0f);
				e.EndColor = .(1.0f, 0.4f, 0.0f, 0.0f);
				e.InitialVelocity = .(0, 4.0f, 0);
				e.VelocityRandomness = .(4.0f, 3.0f, 4.0f);
				e.GravityMultiplier = 0.5f;
				e.BlendMode = .Additive;
				// Per-particle trails
				e.Trail.Enabled = true;
				e.Trail.MaxPoints = 15;
				e.Trail.RecordInterval = 0.1f;
				e.Trail.Lifetime = 0.8f;
				e.Trail.WidthStart = 0.15f;
				e.Trail.WidthEnd = 0.0f;
				e.Trail.UseParticleColor = true;
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(255, 200, 50, 255), "TRAILED");
		}

		// ==================== FORCE FIELD DUST ====================
		{
			let pos = Vector3(-3, 1.5f, 3);
			mForceFieldDustEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mForceFieldDustEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 300;
				e.SpawnRate = 40.0f;
				e.ParticleLifetime = 4.0f;
				e.StartSize = .(0.1f, 0.2f);
				e.EndSize = .(0.15f, 0.3f);
				e.StartColor = .(0.7f, 0.6f, 0.4f, 0.8f);
				e.EndColor = .(0.6f, 0.47f, 0.3f, 0.0f);
				e.InitialVelocity = .(0, 0.1f, 0);
				e.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
				e.GravityMultiplier = 0;
				e.Drag = 0.2f;
				// Multiple force modules
				e.ForceModules.WindForce = .(1.0f, 0.2f, 0.3f);
				e.ForceModules.WindTurbulence = 0.5f;
				e.ForceModules.VortexStrength = 3.0f;
				e.ForceModules.VortexAxis = .(0, 1, 0);
				e.ForceModules.AttractorPosition = .(-5, 2, 5);
				e.ForceModules.AttractorStrength = 5.0f;
				e.ForceModules.AttractorRadius = 8.0f;
				e.IsEmitting = true;
			}
			RegisterEffect(pos, .(180, 150, 100, 255), "FF DUST");
			RegisterEffect(.(-5, 2, 5), .(255, 0, 0, 255), "ATTRACTOR");
		}

		// ==================== FIREWORK SUB-EMITTER ====================
		{
			let pos = Vector3(8, 0, -8);

			// Create explosion emitter first (child)
			mFireworkExplosionEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mFireworkExplosionEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 200;
				e.SpawnRate = 0;
				e.ParticleLifetime = 1.5f;
				e.StartSize = .(0.08f, 0.15f);
				e.EndSize = .(0.02f, 0.04f);
				e.StartColor = .(1.0f, 1.0f, 0.4f, 1.0f);
				e.EndColor = .(1.0f, 0.4f, 0.0f, 0.0f);
				e.InitialVelocity = .(0, 0, 0);
				e.VelocityRandomness = .(8.0f, 8.0f, 8.0f);
				e.GravityMultiplier = 0.8f;
				e.Drag = 0.3f;
				e.BlendMode = .Additive;
				e.SubEmitterOnly = true;
				e.IsEmitting = false;
			}

			// Create firework shell emitter (parent)
			mFireworkEmitter = mWorld.CreateParticleEmitter(mDevice);
			if (let e = mWorld.GetParticleEmitter(mFireworkEmitter))
			{
	
				e.Position = pos;
				e.MaxParticles = 5;
				e.SpawnRate = 0;
				e.ParticleLifetime = 1.2f;
				e.StartSize = .(0.15f, 0.2f);
				e.EndSize = .(0.1f, 0.15f);
				e.StartColor = .(1.0f, 1.0f, 0.4f, 1.0f);
				e.EndColor = .(1.0f, 0.8f, 0.2f, 0.8f);
				e.InitialVelocity = .(0, 15.0f, 0);
				e.VelocityRandomness = .(1.0f, 2.0f, 1.0f);
				e.GravityMultiplier = 1.0f;
				e.BlendMode = .Additive;
				e.IsEmitting = false;
				// Sub-emitter: explode on death
				if (mFireworkExplosionEmitter.IsValid)
				{
					e.SubEmitters[0] = .()
					{
						Trigger = .OnDeath,
						ChildEmitter = mFireworkExplosionEmitter,
						SpawnCount = 40,
						Probability = 1.0f,
						InheritPosition = true,
						InheritVelocity = false,
						InheritColor = true,
						VelocityInheritFactor = 0
					};
					e.SubEmitterCount = 1;
				}
			}
			RegisterEffect(pos, .(255, 255, 100, 255), "FIREWORK");
		}

		// Print legend
		Console.WriteLine("\n=== PARTICLE EFFECTS LEGEND ===");
		for (let label in mParticleLabels)
			Console.WriteLine($"  [{label.Name}] at ({label.Position.X}, {label.Position.Y}, {label.Position.Z})");
		Console.WriteLine("================================\n");
	}

	private void CreateSprites()
	{
		for (int i = 0; i < 10; i++)
		{
			float angle = (float)i / 10.0f * Math.PI_f * 2.0f;
			float radius = 8.0f;

			let spriteHandle = mWorld.CreateSprite();
			if (let sprite = mWorld.GetSprite(spriteHandle))
			{
				sprite.Position = .(
					Math.Cos(angle) * radius,
					2.0f + (float)i * 0.3f,
					Math.Sin(angle) * radius
				);
				sprite.Size = .(1.0f, 1.0f);
				sprite.Color = .((uint8)(128 + i * 12), (uint8)(200 - i * 10), (uint8)(100 + i * 15), 255);
				sprite.IsActive = true;
			}
			mSprites.Add(spriteHandle);
		}
	}

	private void CreateTrail()
	{
		// Orbiting trail (cyan, thin)
		mTrailHandle = mWorld.CreateTrailEmitter();
		if (let trail = mWorld.GetTrailEmitter(mTrailHandle))
		{
			trail.MaxPoints = 50;
			trail.Lifetime = 1.5f;
			trail.WidthStart = 0.15f;
			trail.WidthEnd = 0.0f;
			trail.MinVertexDistance = 0.1f;
			trail.Color = .(0, 1, 1, 1);
			trail.BlendMode = .Additive;
			trail.IsEnabled = true;
			trail.Emitter = new TrailEmitter(mDevice, 50);
		}
		RegisterEffect(.(0, 3, 15), .(0, 255, 255, 255), "ORBIT TRAIL");

		// Sword swing trail (purple, wide ribbon)
		mSwordTrailHandle = mWorld.CreateTrailEmitter();
		if (let trail = mWorld.GetTrailEmitter(mSwordTrailHandle))
		{
			trail.MaxPoints = 30;
			trail.Lifetime = 0.2f;
			trail.WidthStart = 0.8f;
			trail.WidthEnd = 0.2f;
			trail.MinVertexDistance = 0.05f;
			trail.Color = .(0.7f, 0.4f, 1.0f, 0.8f);
			trail.BlendMode = .Additive;
			trail.IsEnabled = true;
			trail.Emitter = new TrailEmitter(mDevice, 30);
		}
		RegisterEffect(.(8, 2, 15), .(180, 100, 255, 255), "SWORD TRAIL");
	}

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
					LoadFoxTexture(modelMesh);

					// Create fox material
					MaterialInstance foxMat = null;
					let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
					if (baseMat != null)
					{
						foxMat = new MaterialInstance(baseMat);
						foxMat.SetColor("BaseColor", .(1, 1, 1, 1));
						foxMat.SetFloat("Metallic", 0.0f);
						foxMat.SetFloat("Roughness", 0.6f);
						if (mFoxTextureHandle.IsValid)
						{
							if (let texView = mRenderSystem.ResourceManager.GetTextureView(mFoxTextureHandle))
								foxMat.SetTexture("AlbedoMap", texView);
						}
						mMaterials.Add(foxMat);
					}

					mFoxProxy = mWorld.CreateSkinnedMesh();
					if (let proxy = mWorld.GetSkinnedMesh(mFoxProxy))
					{
						proxy.MeshHandle = mFoxMeshHandle;
						proxy.BoneBufferHandle = mBoneBufferHandle;
						proxy.Materials[0] = foxMat ?? mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
						proxy.MaterialCount = 1;
						proxy.SetLocalBounds(skinnedMesh.Bounds);
						proxy.BoneCount = boneCount;
						// Position fox outside the cube grid
						proxy.SetTransformImmediate(Matrix.CreateScale(0.05f) * Matrix.CreateTranslation(.(15, 0, 0)));
						proxy.Flags = .DefaultOpaque;
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

	private void LoadFoxTexture(ModelMesh modelMesh)
	{
		let texPath = scope $"{AssetDirectory}/samples/models/Fox/glTF/Texture.png";
		if (ImageLoaderFactory.LoadImage(texPath) case .Ok(var image))
		{
			defer delete image;
			int pixelCount = (int)image.Width * (int)image.Height;
			int channels = image.Data.Length / pixelCount;
			uint8* pixelData = image.Data.Ptr;
			uint8[] rgbaData = null;

			if (channels == 3)
			{
				rgbaData = new uint8[pixelCount * 4];
				for (int p = 0; p < pixelCount; p++)
				{
					rgbaData[p * 4 + 0] = image.Data[p * 3 + 0];
					rgbaData[p * 4 + 1] = image.Data[p * 3 + 1];
					rgbaData[p * 4 + 2] = image.Data[p * 3 + 2];
					rgbaData[p * 4 + 3] = 255;
				}
				pixelData = &rgbaData[0];
			}

			let texData = TextureData.Create2D(pixelData, (uint64)image.Width * (uint64)image.Height * 4, image.Width, image.Height, Sedulous.Textures.TextureFormatUtils.Convert(image.Format));
			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
				mFoxTextureHandle = texHandle;
			delete rgbaData;
		}
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * 0.003f;
			mPitch -= mouse.DeltaY * 0.003f;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}

		// Cycle Fox animation with Space
		if (mClips != null && mClips.Count > 0 && mPlayer != null && keyboard.IsKeyPressed(.Space))
		{
			mCurrentAnimIndex = (mCurrentAnimIndex + 1) % (int32)mClips.Count;
			mClips[mCurrentAnimIndex].IsLooping = true;
			mPlayer.Play(mClips[mCurrentAnimIndex]);
			Console.WriteLine("Playing: {}", mClips[mCurrentAnimIndex].Name);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		float totalTime = (float)frame.TotalTime;
		let keyboard = mShell.InputManager.Keyboard;

		// Light direction control
		float lightSpeed = dt;
		bool lightChanged = false;
		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);

		if (keyboard.IsKeyDown(.Z)) { mLightIntensity = Math.Max(0.1f, mLightIntensity - dt); lightChanged = true; }
		if (keyboard.IsKeyDown(.X)) { mLightIntensity = Math.Min(5.0f, mLightIntensity + dt); lightChanged = true; }
		if (lightChanged) UpdateSunLight();

		// Camera movement
		float speed = (keyboard.IsKeyDown(.LeftShift) ? 30.0f : 15.0f) * dt;
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
		if (move.LengthSquared() > 0) mCameraPosition += Vector3.Normalize(move) * speed;

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));

		// Update Fox animation
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

		// Update trail emitter (orbiting motion)
		if (mTrailHandle.IsValid)
		{
			if (let trail = mWorld.GetTrailEmitter(mTrailHandle))
			{
				if (trail.Emitter != null)
				{
					mTrailAngle += dt * 2.0f;
					float trailRadius = 3.0f;
					float height = Math.Sin(mTrailAngle * 0.5f) * 1.5f;
					let pos = Vector3(
						Math.Cos(mTrailAngle) * trailRadius,
						3.0f + height,
						15.0f + Math.Sin(mTrailAngle) * trailRadius
					);

					let color = Color(
						(uint8)(128 + Math.Sin(mTrailAngle * 3) * 127),
						255,
						(uint8)(200 + Math.Cos(mTrailAngle * 2) * 55),
						255
					);

					trail.Emitter.AddPoint(pos, 0.15f, color);
				}
			}
		}

		// Update sword trail (pendulum swing motion)
		if (mSwordTrailHandle.IsValid)
		{
			if (let trail = mWorld.GetTrailEmitter(mSwordTrailHandle))
			{
				if (trail.Emitter != null)
				{
					float swingAngle = Math.Sin(totalTime * 3.0f) * 1.5f;
					float swingX = Math.Sin(swingAngle) * 2.0f;
					float swingY = 2.0f + Math.Abs(Math.Cos(swingAngle)) * 1.0f;
					let pos = Vector3(8 + swingX, swingY, 15);

					trail.Emitter.AddPoint(pos, 0.8f, .(180, 100, 255, 200));
				}
			}
		}

		// Update debug drawing
		UpdateDebugDrawing(totalTime, dt);

		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	private void UpdateDebugDrawing(float totalTime, float dt)
	{
		if (mOverlayFeature == null) return;

		// FPS counter
		let fps = (dt > 0) ? (1.0f / dt) : 0;
		let fpsText = scope String();
		fpsText.AppendF("FPS: {0:0.0}", fps);
		mOverlayFeature.AddText2D(fpsText, 10, 10, .(255, 255, 0, 255), 2.0f);

		// Ground grid
		mOverlayFeature.AddGrid(.(0, 0.01f, 0), 20, 10, .(128, 128, 128, 80));

		// Axes at origin
		mOverlayFeature.AddAxes(.(0, 0.05f, 0), 2.0f);

		// Light direction arrow
		float cosLP = Math.Cos(mLightPitch);
		let lightDir = Vector3.Normalize(.(
			Math.Sin(mLightYaw) * cosLP,
			Math.Sin(mLightPitch),
			Math.Cos(mLightYaw) * cosLP
		));
		let lightStart = Vector3(0, 5, 0);
		let lightEnd = lightStart + lightDir * 5.0f;
		mOverlayFeature.AddLine(lightStart, lightEnd, .(255, 255, 0, 255));

		// Wireframe box around fox
		mOverlayFeature.AddBox(BoundingBox(Vector3(13.5f, 0, -1.5f), Vector3(16.5f, 3.0f, 1.5f)), .(255, 0, 255, 255));

		// Wireframe sphere at particle effects
		mOverlayFeature.AddSphere(.(0, 1.5f, -15), 1.0f, .(255, 100, 0, 200), 12);  // Fire
		mOverlayFeature.AddSphere(.(-12, 2, -8), 1.0f, .(100, 180, 255, 200), 12);   // Fountain
		mOverlayFeature.AddSphere(.(12, 2.5f, 0), 1.0f, .(150, 100, 255, 200), 12);  // Sparkle

		// Animated marker at trail head
		float trailRadius = 3.0f;
		float trailHeight = Math.Sin(mTrailAngle * 0.5f) * 1.5f;
		let trailPos = Vector3(
			Math.Cos(mTrailAngle) * trailRadius,
			3.0f + trailHeight,
			15.0f + Math.Sin(mTrailAngle) * trailRadius
		);
		mOverlayFeature.AddSphere(trailPos, 0.15f, .(0, 255, 255, 255), 8);

		// Compute camera right/up for billboarded text
		let cameraRight = Vector3.Normalize(Vector3.Cross(mCameraForward, .(0, 1, 0)));
		let cameraUp = Vector3.Normalize(Vector3.Cross(cameraRight, mCameraForward));

		// Draw diamond markers and text labels at each particle effect
		for (let label in mParticleLabels)
		{
			let pos = label.Position;
			let color = label.MarkerColor;

			// Diamond marker
			let size = 0.5f;
			let top = pos + .(0, size * 1.5f, 0);
			let bottom = pos - .(0, size * 0.5f, 0);
			let center = pos + .(0, size * 0.5f, 0);

			// Vertical line
			mOverlayFeature.AddLine(top, bottom, color);

			// Cross at center
			mOverlayFeature.AddLine(center + .(size, 0, 0), center - .(size, 0, 0), color);
			mOverlayFeature.AddLine(center + .(0, 0, size), center - .(0, 0, size), color);

			// Connect to top and bottom to form diamond shape
			mOverlayFeature.AddLine(top, center + .(size, 0, 0), color);
			mOverlayFeature.AddLine(top, center - .(size, 0, 0), color);
			mOverlayFeature.AddLine(top, center + .(0, 0, size), color);
			mOverlayFeature.AddLine(top, center - .(0, 0, size), color);

			mOverlayFeature.AddLine(bottom, center + .(size, 0, 0), color);
			mOverlayFeature.AddLine(bottom, center - .(size, 0, 0), color);
			mOverlayFeature.AddLine(bottom, center + .(0, 0, size), color);
			mOverlayFeature.AddLine(bottom, center - .(0, 0, size), color);

			// Text label above marker
			let textPos = top + .(0, 0.3f, 0);
			mOverlayFeature.AddTextCentered(label.Name, textPos, color, 1.5f, cameraRight, cameraUp);
		}
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mCameraPosition, mCameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mCubeMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mFloorMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);
		if (mFoxMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFoxMeshHandle, mRenderSystem.FrameNumber);
		if (mBoneBufferHandle.IsValid) mRenderSystem.ResourceManager.ReleaseBoneBuffer(mBoneBufferHandle, mRenderSystem.FrameNumber);
		if (mFoxTextureHandle.IsValid) mRenderSystem.ResourceManager.ReleaseTexture(mFoxTextureHandle, mRenderSystem.FrameNumber);
		mRenderSystem?.Shutdown();
		Console.WriteLine("Render Integrated shutting down");
	}
}
