using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(JFAManager))]
public class JFAManagerEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        JFAManager jfaManager = (JFAManager)target;
        if(GUILayout.Button("Calculate distance"))
        {
            jfaManager.CalculateDistance();
        }
    }
}
