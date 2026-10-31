package com.smartplant.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.smartplant.domain.entity.AlarmEvent;
import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface AlarmEventMapper extends BaseMapper<AlarmEvent> {
}
