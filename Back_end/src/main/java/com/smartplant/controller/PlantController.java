package com.smartplant.controller;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.smartplant.common.ApiResponse;
import com.smartplant.domain.entity.DeviceLatest;
import com.smartplant.domain.entity.PlantSnapshot;
import com.smartplant.dto.PlantPayload;
import com.smartplant.service.PlantService;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/plant")
@RequiredArgsConstructor
public class PlantController {

    private final PlantService plantService;

    @GetMapping("/latest")
    public ApiResponse<DeviceLatest> latest() {
        return ApiResponse.ok(plantService.getLatest());
    }

    @GetMapping("/history")
    public ApiResponse<Map<String, Object>> history(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime to,
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "1") long page,
            @RequestParam(defaultValue = "20") long size) {
        Page<PlantSnapshot> result = plantService.history(from, to, page, size, keyword);
        Map<String, Object> data = new HashMap<>();
        data.put("records", result.getRecords());
        data.put("total", result.getTotal());
        data.put("page", result.getCurrent());
        data.put("size", result.getSize());
        return ApiResponse.ok(data);
    }

    /**
     * 主节点 HTTP 汇总上报。鉴权：Header X-Gateway-Key 或 Bearer JWT。
     */
    @PostMapping("/report")
    public ApiResponse<PlantSnapshot> report(@RequestBody PlantPayload payload) {
        PlantSnapshot snapshot = plantService.ingest(payload, "http", null, null);
        return ApiResponse.ok("上报成功", snapshot);
    }
}
