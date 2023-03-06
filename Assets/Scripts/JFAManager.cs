using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class JFAManager : MonoBehaviour
{
    public Texture texture;
    public Material mat;
    private JumpFlood jumpFlood;

    private void OnEnable()
    {
        jumpFlood = new JumpFlood();
    }

    public void CalculateDistance()
    {
        mat.SetTexture("_BaseMap",jumpFlood.JumpFloodDistance(texture));
    }

    private void Update()
    {
        mat.SetTexture("_BaseMap",jumpFlood.JumpFloodDistance(texture));
    }
}
