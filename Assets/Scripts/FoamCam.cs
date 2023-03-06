using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class FoamCam : MonoBehaviour
{
    public Transform followTransform;
    public Material waterMaterial;
    public int textureWidth;
    public int textureHeight;
    private Camera cam;
    private CustomRenderTexture source;
    private JumpFlood jumpFlood;
    private float camOrthographicSize;

    private void Awake()
    {
        source = new CustomRenderTexture(textureWidth, textureHeight, RenderTextureFormat.ARGBFloat);
        cam = gameObject.GetComponent<Camera>();
        cam.targetTexture = source;
        jumpFlood = new JumpFlood();
        camOrthographicSize = cam.orthographicSize;
    }

    void Update()
    {
        var position = transform.position;
        Vector4 corners = new Vector4(position.x - camOrthographicSize, position.z - camOrthographicSize, 
            position.x + camOrthographicSize, position.z + camOrthographicSize);
        Debug.Log($"{corners}");
        waterMaterial.SetVector("_FoamLineCorners", corners);
        waterMaterial.SetTexture("_FoamMap", jumpFlood.JumpFloodDistance(source));
    }
}
