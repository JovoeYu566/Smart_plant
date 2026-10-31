package com.smartplant.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

import java.util.Map;

@Data
public class ControlCommandRequest {

    @NotBlank
    private String action;

    private Map<String, Object> params;
}
