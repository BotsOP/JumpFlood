using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class JumpFlood
{
    private CustomRenderTexture rt1;
    private CustomRenderTexture rt2;
    private int textureWidth = 1024;
    private int textureHeight = 1024;

    private ComputeShader JFA;
    private int SeedKernel;
    private int FloodKernel;
    private int FillDistanceKernel;
    private bool pingPongTexture;
    private Vector3 threadGroupSize;
    private CustomRenderTexture resultTexture => pingPongTexture ? rt1 : rt2;
    private CustomRenderTexture sourceTexture => pingPongTexture ? rt2 : rt1;

    public JumpFlood()
    {
        JFA = Resources.Load<ComputeShader>("JFA");
        SeedKernel = JFA.FindKernel("Seed");
        FloodKernel = JFA.FindKernel("Flood");
        FillDistanceKernel = JFA.FindKernel("FillDistance");
    }

    public CustomRenderTexture JumpFloodDistance(Texture startTexture)
    {
        if (startTexture.width != textureWidth || startTexture.height != textureHeight)
        {
            textureWidth = startTexture.width;
            textureHeight = startTexture.height;
            
            JFA.GetKernelThreadGroupSizes(SeedKernel, out uint threadGroupSizeX, out uint threadGroupSizeY, out _);
        
            threadGroupSize.x = Mathf.CeilToInt((float)textureWidth / threadGroupSizeX);
            threadGroupSize.y = Mathf.CeilToInt((float)textureHeight / threadGroupSizeY);
            
            CreateRT();
        }
        
        Graphics.Blit(startTexture, rt1);
        rt2.Release();
        
        FirstIteration();
        int stepAmount = (int)Mathf.Log(Mathf.Max(textureWidth, textureHeight), 2);
        for (int i = 0; i < stepAmount; i++)
        {
            int step = (int)Mathf.Pow(2, stepAmount - i - 1);
            Flood(step);
        }
        FillDistance();

        return resultTexture;
    }

    private void FirstIteration()
    {
        JFA.SetTexture(SeedKernel, "_Source", sourceTexture);
        JFA.SetTexture(SeedKernel, "_Result", resultTexture);
        JFA.SetInt("_TextureWidth", textureWidth);
        JFA.SetInt("_TextureHeight", textureHeight);
        JFA.Dispatch(SeedKernel, (int)threadGroupSize.x, (int)threadGroupSize.y, 1);
        pingPongTexture = !pingPongTexture;
    }
    private void Flood(int step)
    {
        JFA.SetTexture(FloodKernel, "_Source", sourceTexture);
        JFA.SetTexture(FloodKernel, "_Result", resultTexture);
        JFA.SetInt("_Step", step);
        JFA.Dispatch(FloodKernel, (int)threadGroupSize.x, (int)threadGroupSize.y, 1);
        pingPongTexture = !pingPongTexture;
    }
    private void FillDistance()
    {
        JFA.SetTexture(FillDistanceKernel, "_Source", sourceTexture);
        JFA.SetTexture(FillDistanceKernel, "_Result", resultTexture);
        JFA.Dispatch(FillDistanceKernel, (int)threadGroupSize.x, (int)threadGroupSize.y, 1);
    }

    private void CreateRT()
    {
        rt1 = new CustomRenderTexture(textureWidth, textureHeight, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear)
        {
            enableRandomWrite = true
        };
        rt2 = new CustomRenderTexture(textureWidth, textureHeight, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear)
        {
            enableRandomWrite = true
        };
    }
}
