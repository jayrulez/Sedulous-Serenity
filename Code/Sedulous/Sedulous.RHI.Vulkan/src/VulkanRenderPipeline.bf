namespace Sedulous.RHI.Vulkan;

using System;
using System.Collections;
using Bulkan;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan.Internal;

/// Vulkan implementation of IRenderPipeline.
class VulkanRenderPipeline : IRenderPipeline
{
	private VulkanDevice mDevice;
	private VulkanPipelineLayout mLayout;
	private VkPipeline mPipeline;
	private VkRenderPass mRenderPass;
	private bool mOwnsRenderPass;

	public this(VulkanDevice device, RenderPipelineDescriptor* descriptor, VkRenderPass renderPass = default)
	{
		mDevice = device;
		mLayout = descriptor.Layout as VulkanPipelineLayout;
		mRenderPass = renderPass;
		mOwnsRenderPass = renderPass == default;
		CreatePipeline(descriptor);
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mPipeline != default)
		{
			VulkanNative.vkDestroyPipeline(mDevice.Device, mPipeline, null);
			mPipeline = default;
		}

		if (mOwnsRenderPass && mRenderPass != default)
		{
			VulkanNative.vkDestroyRenderPass(mDevice.Device, mRenderPass, null);
			mRenderPass = default;
		}
	}

	/// Returns true if the pipeline was created successfully.
	public bool IsValid => mPipeline != default;

	public IPipelineLayout Layout => mLayout;

	/// Gets the Vulkan pipeline handle.
	public VkPipeline Pipeline => mPipeline;

	/// Gets the render pass used by this pipeline.
	public VkRenderPass RenderPass => mRenderPass;

	private void CreatePipeline(RenderPipelineDescriptor* descriptor)
	{
		if (mLayout == null || !mLayout.IsValid)
			return;

		// Create render pass if not provided
		if (mRenderPass == default)
		{
			if (!CreateRenderPass(descriptor))
				return;
		}

		// === Shader Stages ===
		List<VkPipelineShaderStageCreateInfo> shaderStages = scope .();

		// Vertex shader (required)
		if (descriptor.Vertex.Shader.Module != null)
		{
			let vkModule = descriptor.Vertex.Shader.Module as VulkanShaderModule;
			if (vkModule != null && vkModule.IsValid)
			{
				String entryPoint = scope :: .(descriptor.Vertex.Shader.EntryPoint);
				shaderStages.Add(.()
					{
						sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
						stage = .VK_SHADER_STAGE_VERTEX_BIT,
						module = vkModule.ShaderModule,
						pName = entryPoint.CStr()
					});
			}
		}

		// Fragment shader (optional)
		if (descriptor.Fragment.HasValue && descriptor.Fragment.Value.Shader.Module != null)
		{
			let fragDesc = descriptor.Fragment.Value;
			let vkModule = fragDesc.Shader.Module as VulkanShaderModule;
			if (vkModule != null && vkModule.IsValid)
			{
				String entryPoint = scope :: .(fragDesc.Shader.EntryPoint);
				shaderStages.Add(.()
					{
						sType = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
						stage = .VK_SHADER_STAGE_FRAGMENT_BIT,
						module = vkModule.ShaderModule,
						pName = entryPoint.CStr()
					});
			}
		}

		if (shaderStages.Count == 0)
			return;

		// === Vertex Input ===
		List<VkVertexInputBindingDescription> bindingDescs = scope .();
		List<VkVertexInputAttributeDescription> attributeDescs = scope .();

		for (uint32 bufferIndex = 0; bufferIndex < descriptor.Vertex.Buffers.Length; bufferIndex++)
		{
			let buffer = descriptor.Vertex.Buffers[bufferIndex];
			bindingDescs.Add(.()
				{
					binding = bufferIndex,
					stride = (uint32)buffer.ArrayStride,
					inputRate = VulkanConversions.ToVkVertexInputRate(buffer.StepMode)
				});

			for (let attr in buffer.Attributes)
			{
				attributeDescs.Add(.()
					{
						location = attr.ShaderLocation,
						binding = bufferIndex,
						format = VulkanConversions.ToVkVertexFormat(attr.Format),
						offset = (uint32)attr.Offset
					});
			}
		}

		VkPipelineVertexInputStateCreateInfo vertexInputInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
				vertexBindingDescriptionCount = (uint32)bindingDescs.Count,
				pVertexBindingDescriptions = bindingDescs.Ptr,
				vertexAttributeDescriptionCount = (uint32)attributeDescs.Count,
				pVertexAttributeDescriptions = attributeDescs.Ptr
			};

		// === Input Assembly ===
		VkPipelineInputAssemblyStateCreateInfo inputAssembly = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
				topology = VulkanConversions.ToVkPrimitiveTopology(descriptor.Primitive.Topology),
				primitiveRestartEnable = descriptor.Primitive.Topology == .TriangleStrip ||
					descriptor.Primitive.Topology == .LineStrip ? VkBool32.True : VkBool32.False
			};

		// === Viewport/Scissor (dynamic) ===
		VkPipelineViewportStateCreateInfo viewportState = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
				viewportCount = 1,
				pViewports = null,  // Dynamic
				scissorCount = 1,
				pScissors = null  // Dynamic
			};

		// === Rasterization ===
		VkPipelineRasterizationStateCreateInfo rasterizer = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
				depthClampEnable = !descriptor.Primitive.DepthClipEnabled ? VkBool32.True : VkBool32.False,
				rasterizerDiscardEnable = VkBool32.False,
				polygonMode = .VK_POLYGON_MODE_FILL,
				cullMode = VulkanConversions.ToVkCullMode(descriptor.Primitive.CullMode),
				frontFace = VulkanConversions.ToVkFrontFace(descriptor.Primitive.FrontFace),
				depthBiasEnable = VkBool32.False,
				depthBiasConstantFactor = 0.0f,
				depthBiasClamp = 0.0f,
				depthBiasSlopeFactor = 0.0f,
				lineWidth = 1.0f
			};

		if (descriptor.DepthStencil.HasValue)
		{
			let ds = descriptor.DepthStencil.Value;
			if (ds.DepthBias != 0 || ds.DepthBiasSlopeScale != 0.0f)
			{
				rasterizer.depthBiasEnable = VkBool32.True;
				rasterizer.depthBiasConstantFactor = (float)ds.DepthBias;
				rasterizer.depthBiasClamp = ds.DepthBiasClamp;
				rasterizer.depthBiasSlopeFactor = ds.DepthBiasSlopeScale;
			}
		}

		// === Multisampling ===
		VkPipelineMultisampleStateCreateInfo multisampling = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
				rasterizationSamples = VulkanConversions.ToVkSampleCount(descriptor.Multisample.Count),
				sampleShadingEnable = VkBool32.False,
				minSampleShading = 1.0f,
				pSampleMask = null,
				alphaToCoverageEnable = descriptor.Multisample.AlphaToCoverageEnabled ? VkBool32.True : VkBool32.False,
				alphaToOneEnable = VkBool32.False
			};

		// === Depth/Stencil ===
		VkPipelineDepthStencilStateCreateInfo depthStencil = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
			};

		if (descriptor.DepthStencil.HasValue)
		{
			let ds = descriptor.DepthStencil.Value;
			depthStencil.depthTestEnable = VkBool32.True;
			depthStencil.depthWriteEnable = ds.DepthWriteEnabled ? VkBool32.True : VkBool32.False;
			depthStencil.depthCompareOp = VulkanConversions.ToVkCompareOp(ds.DepthCompare);
			depthStencil.depthBoundsTestEnable = VkBool32.False;
			depthStencil.stencilTestEnable = VkBool32.False;

			// Front face stencil
			depthStencil.front = .()
				{
					failOp = VulkanConversions.ToVkStencilOp(ds.StencilFront.FailOp),
					passOp = VulkanConversions.ToVkStencilOp(ds.StencilFront.PassOp),
					depthFailOp = VulkanConversions.ToVkStencilOp(ds.StencilFront.DepthFailOp),
					compareOp = VulkanConversions.ToVkCompareOp(ds.StencilFront.Compare),
					compareMask = ds.StencilReadMask,
					writeMask = ds.StencilWriteMask,
					reference = 0
				};

			// Back face stencil
			depthStencil.back = .()
				{
					failOp = VulkanConversions.ToVkStencilOp(ds.StencilBack.FailOp),
					passOp = VulkanConversions.ToVkStencilOp(ds.StencilBack.PassOp),
					depthFailOp = VulkanConversions.ToVkStencilOp(ds.StencilBack.DepthFailOp),
					compareOp = VulkanConversions.ToVkCompareOp(ds.StencilBack.Compare),
					compareMask = ds.StencilReadMask,
					writeMask = ds.StencilWriteMask,
					reference = 0
				};

			// Enable stencil test if any stencil operation is not Keep or compare is not Always
			if (ds.StencilFront.FailOp != .Keep || ds.StencilFront.PassOp != .Keep ||
				ds.StencilFront.DepthFailOp != .Keep || ds.StencilFront.Compare != .Always ||
				ds.StencilBack.FailOp != .Keep || ds.StencilBack.PassOp != .Keep ||
				ds.StencilBack.DepthFailOp != .Keep || ds.StencilBack.Compare != .Always)
			{
				depthStencil.stencilTestEnable = VkBool32.True;
			}
		}

		// === Color Blending ===
		List<VkPipelineColorBlendAttachmentState> colorBlendAttachments = scope .();

		if (descriptor.Fragment.HasValue)
		{
			let fragDesc = descriptor.Fragment.Value;
			for (let target in fragDesc.Targets)
			{
				VkPipelineColorBlendAttachmentState attachment = .()
					{
						colorWriteMask = VulkanConversions.ToVkColorWriteMask(target.WriteMask),
						blendEnable = target.Blend.HasValue ? VkBool32.True : VkBool32.False
					};

				if (target.Blend.HasValue)
				{
					let blend = target.Blend.Value;
					attachment.srcColorBlendFactor = VulkanConversions.ToVkBlendFactor(blend.Color.SrcFactor);
					attachment.dstColorBlendFactor = VulkanConversions.ToVkBlendFactor(blend.Color.DstFactor);
					attachment.colorBlendOp = VulkanConversions.ToVkBlendOp(blend.Color.Operation);
					attachment.srcAlphaBlendFactor = VulkanConversions.ToVkBlendFactor(blend.Alpha.SrcFactor);
					attachment.dstAlphaBlendFactor = VulkanConversions.ToVkBlendFactor(blend.Alpha.DstFactor);
					attachment.alphaBlendOp = VulkanConversions.ToVkBlendOp(blend.Alpha.Operation);
				}
				else
				{
					attachment.srcColorBlendFactor = .VK_BLEND_FACTOR_ONE;
					attachment.dstColorBlendFactor = .VK_BLEND_FACTOR_ZERO;
					attachment.colorBlendOp = .VK_BLEND_OP_ADD;
					attachment.srcAlphaBlendFactor = .VK_BLEND_FACTOR_ONE;
					attachment.dstAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO;
					attachment.alphaBlendOp = .VK_BLEND_OP_ADD;
				}

				colorBlendAttachments.Add(attachment);
			}
		}

		VkPipelineColorBlendStateCreateInfo colorBlending = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
				logicOpEnable = VkBool32.False,
				logicOp = .VK_LOGIC_OP_COPY,
				attachmentCount = (uint32)colorBlendAttachments.Count,
				pAttachments = colorBlendAttachments.Ptr,
				blendConstants = .(0.0f, 0.0f, 0.0f, 0.0f)
			};

		// === Dynamic State ===
		VkDynamicState[4] dynamicStates = .(
			.VK_DYNAMIC_STATE_VIEWPORT,
			.VK_DYNAMIC_STATE_SCISSOR,
			.VK_DYNAMIC_STATE_BLEND_CONSTANTS,
			.VK_DYNAMIC_STATE_STENCIL_REFERENCE
		);

		VkPipelineDynamicStateCreateInfo dynamicState = .()
			{
				sType = .VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
				dynamicStateCount = 4,
				pDynamicStates = &dynamicStates
			};

		// === Create Pipeline ===
		VkGraphicsPipelineCreateInfo pipelineInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
				stageCount = (uint32)shaderStages.Count,
				pStages = shaderStages.Ptr,
				pVertexInputState = &vertexInputInfo,
				pInputAssemblyState = &inputAssembly,
				pTessellationState = null,
				pViewportState = &viewportState,
				pRasterizationState = &rasterizer,
				pMultisampleState = &multisampling,
				pDepthStencilState = &depthStencil,
				pColorBlendState = &colorBlending,
				pDynamicState = &dynamicState,
				layout = mLayout.PipelineLayout,
				renderPass = mRenderPass,
				subpass = 0,
				basePipelineHandle = default,
				basePipelineIndex = -1
			};

		VulkanNative.vkCreateGraphicsPipelines(mDevice.Device, default, 1, &pipelineInfo, null, &mPipeline);
	}

	private bool CreateRenderPass(RenderPipelineDescriptor* descriptor)
	{
		List<VkAttachmentDescription> attachments = scope .();
		List<VkAttachmentReference> colorRefs = scope .();
		VkAttachmentReference depthRef = .();
		bool hasDepth = false;

		// Color attachments
		if (descriptor.Fragment.HasValue)
		{
			let fragDesc = descriptor.Fragment.Value;
			for (let target in fragDesc.Targets)
			{
				uint32 index = (uint32)attachments.Count;
				attachments.Add(.()
					{
						format = VulkanConversions.ToVkFormat(target.Format),
						samples = VulkanConversions.ToVkSampleCount(descriptor.Multisample.Count),
						loadOp = .VK_ATTACHMENT_LOAD_OP_CLEAR,
						storeOp = .VK_ATTACHMENT_STORE_OP_STORE,
						stencilLoadOp = .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
						stencilStoreOp = .VK_ATTACHMENT_STORE_OP_DONT_CARE,
						initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
						finalLayout = .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
					});

				colorRefs.Add(.()
					{
						attachment = index,
						layout = .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
					});
			}
		}

		// Depth attachment
		if (descriptor.DepthStencil.HasValue)
		{
			let ds = descriptor.DepthStencil.Value;
			uint32 index = (uint32)attachments.Count;
			bool hasStencil = VulkanConversions.HasStencilComponent(ds.Format);

			attachments.Add(.()
				{
					format = VulkanConversions.ToVkFormat(ds.Format),
					samples = VulkanConversions.ToVkSampleCount(descriptor.Multisample.Count),
					loadOp = .VK_ATTACHMENT_LOAD_OP_CLEAR,
					storeOp = ds.DepthWriteEnabled ? .VK_ATTACHMENT_STORE_OP_STORE : .VK_ATTACHMENT_STORE_OP_DONT_CARE,
					stencilLoadOp = hasStencil ? .VK_ATTACHMENT_LOAD_OP_CLEAR : .VK_ATTACHMENT_LOAD_OP_DONT_CARE,
					stencilStoreOp = hasStencil ? .VK_ATTACHMENT_STORE_OP_STORE : .VK_ATTACHMENT_STORE_OP_DONT_CARE,
					initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
					finalLayout = .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
				});

			depthRef = .()
				{
					attachment = index,
					layout = .VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
				};
			hasDepth = true;
		}

		VkSubpassDescription subpass = .()
			{
				pipelineBindPoint = .VK_PIPELINE_BIND_POINT_GRAPHICS,
				colorAttachmentCount = (uint32)colorRefs.Count,
				pColorAttachments = colorRefs.Ptr,
				pDepthStencilAttachment = hasDepth ? &depthRef : null
			};

		VkSubpassDependency dependency = .()
			{
				srcSubpass = VulkanNative.VK_SUBPASS_EXTERNAL,
				dstSubpass = 0,
				srcStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | .VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
				dstStageMask = .VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | .VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
				srcAccessMask = 0,
				dstAccessMask = .VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | .VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
			};

		VkRenderPassCreateInfo renderPassInfo = .()
			{
				sType = .VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
				attachmentCount = (uint32)attachments.Count,
				pAttachments = attachments.Ptr,
				subpassCount = 1,
				pSubpasses = &subpass,
				dependencyCount = 1,
				pDependencies = &dependency
			};

		return VulkanNative.vkCreateRenderPass(mDevice.Device, &renderPassInfo, null, &mRenderPass) == .VK_SUCCESS;
	}
}
